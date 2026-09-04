import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    property var usage: null
    property string errorText: ""
    property bool loading: true

    // Budgets are stored in cents (the config UI uses integer spin boxes).
    // Every config read is sanitised: an unset value reads back as undefined,
    // and arithmetic on it would silently poison bindings with NaN.
    readonly property real blockLimit: cfgNumber("blockCostLimit", 0) / 100
    readonly property real dailyLimit: cfgNumber("dailyCostLimit", 0) / 100
    readonly property real weeklyLimit: cfgNumber("weeklyCostLimit", 0) / 100

    function cfgNumber(key, fallback) {
        var v = Number(Plasmoid.configuration[key]);
        return isFinite(v) ? v : fallback;
    }

    readonly property int refreshSecs: Math.max(10, cfgNumber("refreshInterval", 60))
    readonly property string collector: {
        var c = Plasmoid.configuration.scriptPath;
        return (c && String(c).trim() !== "") ? String(c).trim() : "claude-usage";
    }

    Plasmoid.backgroundHints: PlasmaCore.Types.DefaultBackground
    preferredRepresentation: fullRepresentation

    switchWidth: Kirigami.Units.gridUnit * 12
    switchHeight: Kirigami.Units.gridUnit * 10

    // ---------------------------------------------------------------- helpers

    function fmtCost(v) {
        if (v === null || v === undefined) return "--";
        if (v >= 100) return "$" + v.toFixed(0);
        if (v >= 10) return "$" + v.toFixed(1);
        return "$" + v.toFixed(2);
    }

    function fmtTokens(n) {
        if (n === null || n === undefined) return "--";
        if (n >= 1e9) return (n / 1e9).toFixed(1) + "B";
        if (n >= 1e6) return (n / 1e6).toFixed(1) + "M";
        if (n >= 1e3) return (n / 1e3).toFixed(0) + "K";
        return String(n);
    }

    function fmtMins(m) {
        if (m === null || m === undefined) return "--";
        var h = Math.floor(m / 60);
        var mm = Math.round(m % 60);
        return h > 0 ? h + "h " + mm + "m" : mm + "m";
    }

    // Coarser than fmtMins: a weekly window has days left, and "109h 12m"
    // is not what anyone wants to read off a desktop.
    function fmtUntil(m) {
        if (m === null || m === undefined) return "";
        if (m >= 1440) return Math.floor(m / 1440) + "d " + Math.floor((m % 1440) / 60) + "h";
        if (m >= 60) return Math.floor(m / 60) + "h " + (m % 60) + "m";
        return m + "m";
    }

    // ------------------------------------------------------------- limits

    readonly property var limits: usage && usage.limits ? usage.limits : null
    readonly property bool limitsOk: limits !== null && limits.ok === true

    function limitRow(kind) {
        if (!limitsOk) return null;
        for (var i = 0; i < limits.entries.length; i++)
            if (limits.entries[i].kind === kind) return limits.entries[i];
        return null;
    }

    readonly property var sessionLimit: limitRow("session")
    readonly property var weekLimit: limitRow("weekly_all")

    // Model-scoped caps sit at 0% for models you never reach for, so keep
    // them out of the way until they actually carry a number.
    readonly property var limitRows: {
        if (!limitsOk) return [];
        var out = [];
        for (var i = 0; i < limits.entries.length; i++) {
            var e = limits.entries[i];
            if (e.kind === "session" || e.kind === "weekly_all" || e.pct > 0)
                out.push(e);
        }
        return out;
    }

    // Usage credits only matter once they carry a number.
    readonly property string creditsText: {
        if (!limitsOk || !limits.credits) return "";
        var c = limits.credits;
        if (!c.limit && !(c.used > 0)) return "";
        var sym = ({ GBP: "\u00a3", USD: "$", EUR: "\u20ac" })[c.currency] || (c.currency + " ");
        var t = i18n("Usage credits %1", sym + c.used.toFixed(2));
        if (c.limit) t += " / " + sym + c.limit.toFixed(2);
        return t;
    }

    function limitColor(e) {
        if (!e) return Kirigami.Theme.highlightColor;
        if (e.severity === "critical") return Kirigami.Theme.negativeTextColor;
        if (e.severity === "warning") return Kirigami.Theme.neutralTextColor;
        return Kirigami.Theme.highlightColor;
    }

    function limitReset(e) {
        if (!e || e.resets_in_min === null || e.resets_in_min === undefined) return "";
        return e.resets_in_min >= 720
            ? i18n("%1 %2", e.resets_day, e.resets_at_local)
            : fmtUntil(e.resets_in_min);
    }

    // An explicitly configured budget wins, because the user asked for it.
    // Otherwise the real session limit beats "how far through the window we
    // are", which says nothing about how much is left to spend.
    function gauge() {
        if (!usage || !usage.block) return { frac: 0, label: "", warn: false };
        var b = usage.block;
        if (blockLimit > 0) {
            var f = b.cost / blockLimit;
            return {
                frac: Math.min(1, f),
                label: Math.round(f * 100) + "% of " + fmtCost(blockLimit) + " block budget",
                warn: f >= 0.9
            };
        }
        var s = sessionLimit;
        if (s) {
            return {
                frac: Math.min(1, s.pct / 100),
                label: s.resets_in_min !== null
                    ? i18n("%1% of session limit · resets in %2 (%3)",
                           Math.round(s.pct), fmtUntil(s.resets_in_min), s.resets_at_local)
                    : i18n("%1% of session limit", Math.round(s.pct)),
                warn: s.severity !== "normal"
            };
        }
        return {
            frac: Math.min(1, b.time_pct / 100),
            label: b.active ? fmtMins(b.remaining_min) + " left in block" : "block closed",
            warn: false
        };
    }

    function limitPct(value, limit) {
        return limit > 0 ? value / limit : -1;
    }

    // ------------------------------------------------------------ data source

    Plasma5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []

        onNewData: function (source, data) {
            disconnectSource(source);
            root.loading = false;
            if (data["exit code"] !== 0) {
                root.errorText = (data["stderr"] || "").trim()
                    || i18n("Could not run %1", Plasmoid.configuration.scriptPath);
                return;
            }
            var raw = String(data["stdout"] || "").trim();
            if (raw === "") {
                root.errorText = i18n("No output from %1", root.collector);
                return;
            }
            try {
                root.usage = JSON.parse(raw);
                root.errorText = "";
            } catch (e) {
                root.errorText = i18n("Unreadable output from the collector");
            }
        }

        function refresh() {
            // The applet does not inherit an interactive shell, so make sure
            // ~/.local/bin is reachable for the default unqualified command.
            connectSource("PATH=\"$HOME/.local/bin:$PATH\" " + root.collector);
        }
    }

    Timer {
        interval: root.refreshSecs * 1000
        running: true
        repeat: true
        onTriggered: executable.refresh()
    }

    // Don't make the first paint depend on the timer.
    Component.onCompleted: {
        executable.refresh();
    }

    toolTipMainText: i18n("Claude Code Usage")
    toolTipSubText: {
        if (!usage || !usage.block) return i18n("No usage data");
        var lines = [];
        if (sessionLimit)
            lines.push(i18n("Session %1% · resets in %2",
                            Math.round(sessionLimit.pct),
                            fmtUntil(sessionLimit.resets_in_min)));
        if (weekLimit)
            lines.push(i18n("Week %1% · resets %2 %3", Math.round(weekLimit.pct),
                            weekLimit.resets_day, weekLimit.resets_at_local));
        lines.push(i18n("Block %1 · Today %2 · Week %3",
                        fmtCost(usage.block.cost), fmtCost(usage.today.cost),
                        fmtCost(usage.week.cost)));
        return lines.join("\n");
    }

    // -------------------------------------------------------- compact (panel)

    compactRepresentation: MouseArea {
        Layout.minimumWidth: label.implicitWidth + Kirigami.Units.smallSpacing * 2
        onClicked: root.expanded = !root.expanded

        PlasmaComponents.Label {
            id: label
            anchors.centerIn: parent
            text: {
                var cost = root.usage && root.usage.block
                    ? root.fmtCost(root.usage.block.cost) : "--";
                if (Plasmoid.configuration.showLimitInPanel && root.sessionLimit)
                    return cost + " · " + Math.round(root.sessionLimit.pct) + "%";
                return cost;
            }
            // Only the limit can actually stop work, so only it colours here.
            color: root.sessionLimit && root.sessionLimit.severity !== "normal"
                   ? root.limitColor(root.sessionLimit)
                   : Kirigami.Theme.textColor
        }
    }

    // ---------------------------------------------------------- full (desktop)

    fullRepresentation: Item {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 15
        Layout.minimumHeight: Kirigami.Units.gridUnit * 12
        Layout.preferredWidth: Kirigami.Units.gridUnit * 18
        Layout.preferredHeight: contentColumn.implicitHeight
                                + Kirigami.Units.largeSpacing * 2

        PlasmaComponents.Label {
            anchors.centerIn: parent
            width: parent.width - Kirigami.Units.largeSpacing * 2
            visible: root.errorText !== ""
            text: root.errorText
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            opacity: 0.7
        }

        PlasmaComponents.Label {
            id: loadingLabel
            anchors.centerIn: parent
            visible: root.loading && root.usage === null && root.errorText === ""
            text: i18n("Reading usage…")
            opacity: 0.6
        }

        ColumnLayout {
            id: contentColumn
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.smallSpacing
            visible: root.usage !== null && root.errorText === ""

            // --- header
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Icon {
                    source: "utilities-system-monitor"
                    implicitWidth: Kirigami.Units.iconSizes.small
                    implicitHeight: Kirigami.Units.iconSizes.small
                }

                PlasmaExtras.Heading {
                    text: i18n("Claude Code")
                    level: 5
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }

                Rectangle {
                    implicitWidth: Kirigami.Units.smallSpacing
                    implicitHeight: Kirigami.Units.smallSpacing
                    radius: width / 2
                    color: Kirigami.Theme.positiveTextColor
                    opacity: root.usage && root.usage.block
                             && root.usage.block.active ? 1 : 0.25
                }
            }

            // --- rolling block headline
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing

                ColumnLayout {
                    spacing: 0
                    Layout.fillWidth: true

                    PlasmaExtras.Heading {
                        level: 1
                        text: root.usage ? root.fmtCost(root.usage.block.cost) : "--"
                        color: root.gauge().warn
                               ? Kirigami.Theme.negativeTextColor
                               : Kirigami.Theme.textColor
                    }

                    PlasmaComponents.Label {
                        text: root.usage
                              ? i18n("%1h block · %2 msg",
                                     root.usage.block_hours,
                                     root.usage.block.messages)
                              : ""
                        opacity: 0.65
                        font: Kirigami.Theme.smallFont
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }

                ColumnLayout {
                    spacing: 0
                    Layout.alignment: Qt.AlignRight | Qt.AlignBottom

                    PlasmaComponents.Label {
                        Layout.alignment: Qt.AlignRight
                        text: root.usage
                              ? root.fmtTokens(root.usage.block.tokens) : "--"
                    }
                    PlasmaComponents.Label {
                        Layout.alignment: Qt.AlignRight
                        text: i18n("tokens")
                        opacity: 0.65
                        font: Kirigami.Theme.smallFont
                    }
                }
            }

            // --- gauge
            PlasmaComponents.ProgressBar {
                Layout.fillWidth: true
                from: 0
                to: 1
                value: root.gauge().frac
            }

            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: root.gauge().label
                opacity: 0.65
                font: Kirigami.Theme.smallFont
                elide: Text.ElideRight
            }

            // --- burn rate
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                visible: root.usage && root.usage.block
                         && root.usage.block.burn_cost_per_hour !== null

                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    font: Kirigami.Theme.smallFont
                    opacity: 0.8
                    text: root.usage && root.usage.block.burn_cost_per_hour !== null
                          ? i18n("%1/h · %2 tok/min",
                                 root.fmtCost(root.usage.block.burn_cost_per_hour),
                                 root.fmtTokens(root.usage.block.burn_tokens_per_min))
                          : ""
                    elide: Text.ElideRight
                }

                PlasmaComponents.Label {
                    font: Kirigami.Theme.smallFont
                    opacity: 0.8
                    visible: root.usage && root.usage.block
                             && root.usage.block.projected_cost !== null
                    text: root.usage && root.usage.block.projected_cost !== null
                          ? i18n("→ %1", root.fmtCost(root.usage.block.projected_cost))
                          : ""
                }
            }

            // --- plan limits (session / weekly caps from the account)
            Kirigami.Separator {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                visible: limitsBlock.visible || limitsNote.visible
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                visible: limitsBlock.visible || limitsNote.visible
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents.Label {
                    text: i18n("Plan limits")
                    font: Kirigami.Theme.smallFont
                    opacity: 0.65
                    Layout.fillWidth: true
                }

                PlasmaComponents.Label {
                    text: {
                        if (!root.limits) return "";
                        var t = root.limits.plan || "";
                        if (root.limits.stale)
                            t += (t ? " · " : "") + i18n("cached");
                        return t;
                    }
                    font: Kirigami.Theme.smallFont
                    opacity: 0.5
                    elide: Text.ElideRight
                }
            }

            ColumnLayout {
                id: limitsBlock
                Layout.fillWidth: true
                spacing: 2
                visible: Plasmoid.configuration.showLimits
                         && root.limitRows.length > 0

                Repeater {
                    model: root.limitRows

                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        PlasmaComponents.Label {
                            text: modelData.label
                            font: Kirigami.Theme.smallFont
                            elide: Text.ElideRight
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 5
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: Kirigami.Units.smallSpacing
                            radius: height / 2
                            color: Qt.alpha(Kirigami.Theme.textColor, 0.15)

                            Rectangle {
                                width: parent.width * Math.min(1, modelData.pct / 100)
                                height: parent.height
                                radius: parent.radius
                                color: root.limitColor(modelData)
                            }
                        }

                        PlasmaComponents.Label {
                            text: Math.round(modelData.pct) + "%"
                            font: Kirigami.Theme.smallFont
                            horizontalAlignment: Text.AlignRight
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 2
                            color: modelData.severity !== "normal"
                                   ? root.limitColor(modelData)
                                   : Kirigami.Theme.textColor
                        }

                        PlasmaComponents.Label {
                            text: root.limitReset(modelData)
                            font: Kirigami.Theme.smallFont
                            opacity: 0.55
                            horizontalAlignment: Text.AlignRight
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 3.5
                        }
                    }
                }

                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    font: Kirigami.Theme.smallFont
                    opacity: 0.55
                    elide: Text.ElideRight
                    visible: root.creditsText !== ""
                    text: root.creditsText
                }
            }

            PlasmaComponents.Label {
                id: limitsNote
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                font: Kirigami.Theme.smallFont
                opacity: 0.55
                wrapMode: Text.WordWrap
                visible: Plasmoid.configuration.showLimits && root.usage
                         && !root.limitsOk
                text: root.limits && root.limits.reason
                      ? i18n("Limits unavailable — %1", root.limits.reason)
                      : i18n("Limits unavailable")
            }

            Kirigami.Separator {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
            }

            // --- period totals
            GridLayout {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                columns: 4
                columnSpacing: Kirigami.Units.smallSpacing
                rowSpacing: 0

                Repeater {
                    model: root.usage ? [
                        { key: i18n("Today"), val: root.usage.today.cost,
                          pct: root.limitPct(root.usage.today.cost, root.dailyLimit) },
                        { key: i18n("Week"), val: root.usage.week.cost,
                          pct: root.limitPct(root.usage.week.cost, root.weeklyLimit) },
                        { key: i18n("Month"), val: root.usage.month.cost, pct: -1 },
                        { key: i18n("All time"), val: root.usage.total.cost, pct: -1 }
                    ] : []

                    delegate: ColumnLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 0

                        PlasmaComponents.Label {
                            text: root.fmtCost(modelData.val)
                            color: modelData.pct >= 0.9
                                   ? Kirigami.Theme.negativeTextColor
                                   : Kirigami.Theme.textColor
                        }
                        PlasmaComponents.Label {
                            text: modelData.pct >= 0
                                  ? modelData.key + " " + Math.round(modelData.pct * 100) + "%"
                                  : modelData.key
                            opacity: 0.65
                            font: Kirigami.Theme.smallFont
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }
                }
            }

            // --- model breakdown
            Kirigami.Separator {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                visible: modelList.visible
            }

            ColumnLayout {
                id: modelList
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                spacing: 2
                visible: Plasmoid.configuration.showModels
                         && root.usage && root.modelRows.length > 0

                Repeater {
                    model: root.modelRows

                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        PlasmaComponents.Label {
                            text: modelData.name
                            font: Kirigami.Theme.smallFont
                            elide: Text.ElideRight
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 7
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: Kirigami.Units.smallSpacing
                            radius: height / 2
                            color: Qt.alpha(Kirigami.Theme.textColor, 0.15)

                            Rectangle {
                                width: parent.width * modelData.frac
                                height: parent.height
                                radius: parent.radius
                                color: Kirigami.Theme.highlightColor
                            }
                        }

                        PlasmaComponents.Label {
                            text: root.fmtCost(modelData.cost)
                            font: Kirigami.Theme.smallFont
                            opacity: 0.8
                        }
                    }
                }
            }

            // --- recent sessions
            Kirigami.Separator {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                visible: sessionList.visible
            }

            ColumnLayout {
                id: sessionList
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                spacing: 2
                visible: Plasmoid.configuration.showSessions
                         && root.usage && root.usage.sessions.length > 0

                Repeater {
                    model: root.usage ? root.usage.sessions : []

                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        Rectangle {
                            implicitWidth: Kirigami.Units.smallSpacing
                            implicitHeight: Kirigami.Units.smallSpacing
                            radius: width / 2
                            color: modelData.active
                                   ? Kirigami.Theme.positiveTextColor
                                   : Kirigami.Theme.disabledTextColor
                        }

                        PlasmaComponents.Label {
                            text: modelData.project.replace(/^-/, "/").replace(/-/g, "/")
                            font: Kirigami.Theme.smallFont
                            elide: Text.ElideLeft
                            Layout.fillWidth: true
                        }

                        PlasmaComponents.Label {
                            text: root.fmtCost(modelData.cost)
                            font: Kirigami.Theme.smallFont
                            opacity: 0.8
                        }
                    }
                }
            }

            Item { Layout.fillHeight: true }

            PlasmaComponents.Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignRight
                text: root.usage ? i18n("updated %1",
                        root.usage.generated.split("T")[1].substring(0, 5)) : ""
                opacity: 0.45
                font: Kirigami.Theme.smallFont
            }
        }
    }

    // Flatten the model map into a sorted, bar-friendly list.
    readonly property var modelRows: {
        if (!usage || !usage.models) return [];
        var rows = [];
        var max = 0;
        for (var name in usage.models) {
            var c = usage.models[name].cost;
            if (c > max) max = c;
            rows.push({ name: name.replace(/^claude-/, ""), cost: c, frac: 0 });
        }
        rows.sort(function (a, b) { return b.cost - a.cost; });
        rows = rows.slice(0, 4);
        for (var i = 0; i < rows.length; i++)
            rows[i].frac = max > 0 ? rows[i].cost / max : 0;
        return rows;
    }

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Refresh now")
            icon.name: "view-refresh"
            onTriggered: executable.refresh()
        }
    ]
}
