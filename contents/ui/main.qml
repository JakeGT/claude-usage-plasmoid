import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
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
    function cfgBool(key, fallback) {
        var v = Plasmoid.configuration[key];
        return v === undefined || v === null ? fallback : !!v;
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

    // ------------------------------------------------------- design tokens
    // Text always wears theme ink; colour lives on marks (dots, bars, meters).
    readonly property color ink: Kirigami.Theme.textColor
    readonly property color hairline: Qt.alpha(ink, 0.12)
    readonly property color card: Qt.alpha(ink, 0.045)
    readonly property real muted: 0.62
    readonly property real faint: 0.45
    readonly property color accent: Kirigami.Theme.highlightColor
    // Status colours are reserved for state and always come with a label.
    readonly property color good: "#0ca30c"
    readonly property color warning: "#fab219"
    readonly property color critical: "#d03b3b"
    // Model families keep a fixed colour (validated categorical order for a
    // dark surface), so a family never changes colour between windows.
    readonly property var familyColors: ({
        opus: "#3987e5", sonnet: "#d95926", haiku: "#199e70",
        fable: "#c98500", other: Qt.alpha(ink, 0.4)
    })
    readonly property var familyNames: ({
        opus: "Opus", sonnet: "Sonnet", haiku: "Haiku", fable: "Fable", other: "Other"
    })

    readonly property int fsHero: Kirigami.Theme.defaultFont.pointSize + 16
    readonly property int fsValue: Kirigami.Theme.defaultFont.pointSize + 3
    readonly property int fsBody: Kirigami.Theme.defaultFont.pointSize
    readonly property int fsSmall: Kirigami.Theme.defaultFont.pointSize - 1
    readonly property int fsTiny: Kirigami.Theme.defaultFont.pointSize - 2
    readonly property real gap: Kirigami.Units.smallSpacing
    readonly property real pad: Kirigami.Units.largeSpacing

    // ---------------------------------------------------------------- helpers

    function fmtCost(v) {
        if (v === null || v === undefined) return "--";
        if (v >= 1000) return "$" + Math.round(v).toLocaleString(Qt.locale("en_US"), "f", 0);
        if (v >= 100) return "$" + v.toFixed(0);
        if (v >= 10) return "$" + v.toFixed(1);
        return "$" + v.toFixed(2);
    }

    function fmtTokens(n) {
        if (n === null || n === undefined) return "--";
        if (n >= 1e9) return (n / 1e9).toFixed(1) + "B";
        if (n >= 1e8) return (n / 1e6).toFixed(0) + "M";
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

    function fmtAgo(m) {
        if (m === null || m === undefined) return "";
        if (m < 1) return i18n("just now");
        return i18n("%1 ago", fmtUntil(m));
    }

    function familyOf(model) {
        var m = String(model || "").toLowerCase();
        if (m.indexOf("fable") >= 0 || m.indexOf("mythos") >= 0) return "fable";
        if (m.indexOf("opus") >= 0) return "opus";
        if (m.indexOf("sonnet") >= 0) return "sonnet";
        if (m.indexOf("haiku") >= 0) return "haiku";
        return "other";
    }

    function shortModel(model) {
        return String(model || "").replace(/^claude-/, "").replace(/\[.*\]$/, "");
    }

    // ------------------------------------------------------------- limits

    readonly property var limits: usage && usage.limits ? usage.limits : null
    readonly property bool limitsOk: limits !== null && limits.ok === true
    readonly property bool showLimits: cfgBool("showLimits", true)

    function limitRow(kind) {
        if (!limitsOk) return null;
        for (var i = 0; i < limits.entries.length; i++)
            if (limits.entries[i].kind === kind) return limits.entries[i];
        return null;
    }

    readonly property var sessionLimit: limitRow("session")
    readonly property var weekLimit: limitRow("weekly_all")

    // Every row below the hero: weekly caps, plus model-scoped caps once they
    // carry a number (they sit at 0% for models you never reach for).
    readonly property var secondaryLimits: {
        if (!limitsOk) return [];
        var out = [];
        for (var i = 0; i < limits.entries.length; i++) {
            var e = limits.entries[i];
            if (e.kind === "session") continue;
            if (e.kind === "weekly_all" || e.pct > 0) out.push(e);
        }
        return out;
    }

    // Usage credits only matter once they carry a number.
    readonly property string creditsText: {
        if (!limitsOk || !limits.credits) return "";
        var c = limits.credits;
        if (!c.limit && !(c.used > 0)) return "";
        var sym = ({ GBP: "£", USD: "$", EUR: "€" })[c.currency] || (c.currency + " ");
        var t = i18n("Usage credits %1", sym + c.used.toFixed(2));
        if (c.limit) t += " / " + sym + c.limit.toFixed(2);
        return t;
    }

    function severityColor(sev) {
        if (sev === "critical") return critical;
        if (sev === "warning") return warning;
        return accent;
    }
    function severityWord(sev) {
        if (sev === "critical") return i18n("at limit");
        if (sev === "warning") return i18n("near limit");
        return "";
    }

    function limitReset(e) {
        if (!e || e.resets_in_min === null || e.resets_in_min === undefined) return "";
        return e.resets_in_min >= 720
            ? i18n("%1 %2", e.resets_day, e.resets_at_local)
            : fmtUntil(e.resets_in_min);
    }

    // How far through its window a limit is (0..1), or -1 when unknown.
    function elapsedFrac(e) {
        if (!e || !e.window_min || e.resets_in_min === null || e.resets_in_min === undefined) return -1;
        return Math.max(0, Math.min(1, 1 - e.resets_in_min / e.window_min));
    }
    function paceText(e) {
        var f = elapsedFrac(e);
        if (f < 0) return "";
        var used = e.pct / 100;
        var lead = Math.round((used - f) * 100);
        return i18n("%1% used with %2% of the window gone", Math.round(e.pct), Math.round(f * 100))
             + "\n" + (lead > 2 ? i18n("Ahead of an even pace by %1 points", lead)
                       : lead < -2 ? i18n("Under an even pace by %1 points", -lead)
                       : i18n("On an even pace"));
    }

    function budgetFrac(value, limit) {
        return limit > 0 ? value / limit : -1;
    }

    // Headline gauge, kept for the panel tooltip: an explicit block budget
    // wins, then the real session limit, then time through the block.
    function gauge() {
        if (!usage || !usage.block) return { frac: 0, label: "", warn: false };
        var b = usage.block;
        if (blockLimit > 0) {
            var f = b.cost / blockLimit;
            return { frac: Math.min(1, f), warn: f >= 0.9,
                     label: i18n("%1% of %2 block budget", Math.round(f * 100), fmtCost(blockLimit)) };
        }
        var s = sessionLimit;
        if (s) return { frac: Math.min(1, s.pct / 100), warn: s.severity !== "normal",
                        label: i18n("%1% of session limit", Math.round(s.pct)) };
        return { frac: Math.min(1, b.time_pct / 100), warn: false,
                 label: b.active ? i18n("%1 left in block", fmtMins(b.remaining_min)) : i18n("block closed") };
    }

    // ------------------------------------------------------------ chart data

    readonly property var daily: usage && usage.daily ? usage.daily : []
    readonly property var familiesInChart: {
        var order = usage && usage.families ? usage.families : ["opus", "sonnet", "haiku", "fable", "other"];
        var out = [];
        for (var i = 0; i < order.length; i++) {
            for (var d = 0; d < daily.length; d++) {
                if ((daily[d].families[order[i]] || 0) > 0) { out.push(order[i]); break; }
            }
        }
        return out;
    }
    readonly property real dailyMax: {
        var m = 0;
        for (var i = 0; i < daily.length; i++) m = Math.max(m, daily[i].cost);
        return m;
    }

    // Flatten the model map into a sorted, bar-friendly list.
    readonly property var modelRows: {
        if (!usage || !usage.models) return [];
        var rows = [];
        var max = 0;
        for (var name in usage.models) {
            var c = usage.models[name].cost;
            if (!(c > 0)) continue;
            if (c > max) max = c;
            rows.push({ name: shortModel(name), family: familyOf(name), cost: c, frac: 0 });
        }
        rows.sort(function (a, b) { return b.cost - a.cost; });
        rows = rows.slice(0, 4);
        for (var i = 0; i < rows.length; i++)
            rows[i].frac = max > 0 ? rows[i].cost / max : 0;
        return rows;
    }

    readonly property real sessionMax: {
        var m = 0;
        var s = usage && usage.sessions ? usage.sessions : [];
        for (var i = 0; i < s.length; i++) m = Math.max(m, s[i].cost);
        return m;
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
                    || i18n("Could not run %1", root.collector);
                return;
            }
            var raw = String(data["stdout"] || "").trim();
            if (raw === "") {
                root.errorText = i18n("No output from %1", root.collector);
                return;
            }
            try {
                var parsed = JSON.parse(raw);
                if (parsed.error) { root.errorText = String(parsed.error); return; }
                root.usage = parsed;      // the previous render stays until this lands
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
    Component.onCompleted: executable.refresh()

    toolTipMainText: i18n("Claude Code Usage")
    toolTipSubText: {
        if (!usage || !usage.block) return i18n("No usage data");
        var lines = [];
        if (sessionLimit)
            lines.push(i18n("Session %1% · resets in %2",
                            Math.round(sessionLimit.pct), fmtUntil(sessionLimit.resets_in_min)));
        if (weekLimit)
            lines.push(i18n("Week %1% · resets %2 %3", Math.round(weekLimit.pct),
                            weekLimit.resets_day, weekLimit.resets_at_local));
        lines.push(i18n("Block %1 · Today %2 · 7 days %3",
                        fmtCost(usage.block.cost), fmtCost(usage.today.cost), fmtCost(usage.week.cost)));
        return lines.join("\n");
    }

    // ------------------------------------------------------ reusable pieces

    component Muted: PlasmaComponents.Label {
        color: root.ink; opacity: root.muted; font.pointSize: root.fsSmall
        elide: Text.ElideRight
    }
    component SectionTitle: PlasmaComponents.Label {
        color: root.ink; opacity: root.muted; font.pointSize: root.fsSmall
        font.weight: Font.DemiBold; font.capitalization: Font.AllUppercase
        font.letterSpacing: 0.6
        elide: Text.ElideRight
    }
    component Dot: Rectangle {
        property color fill: root.ink
        implicitWidth: Math.round(Kirigami.Units.gridUnit * 0.45); implicitHeight: implicitWidth
        radius: width / 2; color: fill
        Layout.alignment: Qt.AlignVCenter
    }
    // Meter: the fill carries severity, the track is a lighter step of the
    // same colour, and an ink tick marks how far through the window we are.
    component Meter: Item {
        property real frac: 0
        property color fill: root.accent
        property real pace: -1
        property real thickness: 6
        implicitHeight: thickness + 4
        Layout.fillWidth: true
        Rectangle {
            id: track
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width; height: parent.thickness; radius: height / 2
            color: Qt.alpha(parent.fill, 0.22)
            Rectangle {
                width: Math.max(parent.height, parent.width * Math.min(1, Math.max(0, frac)))
                visible: frac > 0
                height: parent.height; radius: parent.radius
                color: fill
            }
        }
        Rectangle {
            visible: pace >= 0
            x: Math.round(pace * (parent.width - width))
            anchors.verticalCenter: parent.verticalCenter
            width: 2; height: parent.thickness + 6; radius: 1
            color: root.ink
            opacity: 0.85
        }
    }
    // A bar segment with a rounded data-end and a square base.
    component Seg: Item {
        property color fill
        property bool roundTop: true
        Rectangle {
            anchors.fill: parent
            radius: parent.roundTop ? Math.min(3, parent.width / 2, parent.height / 2) : 0
            color: parent.fill
        }
        Rectangle {
            visible: parent.roundTop && parent.height > 4
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: parent.height / 2
            color: parent.fill
        }
    }
    component StatTile: Rectangle {
        property string label
        property string value
        property string sub
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        radius: Kirigami.Units.cornerRadius
        color: root.card
        implicitHeight: tileCol.implicitHeight + root.gap * 2
        ColumnLayout {
            id: tileCol
            anchors { fill: parent; margins: root.gap; leftMargin: root.gap * 2; rightMargin: root.gap * 2 }
            spacing: 0
            Muted { text: label; font.pointSize: root.fsTiny; Layout.fillWidth: true }
            PlasmaComponents.Label {
                text: value
                color: root.ink; font.pointSize: root.fsValue; font.weight: Font.DemiBold
                elide: Text.ElideRight; Layout.fillWidth: true
            }
            Muted { text: sub; font.pointSize: root.fsTiny; opacity: root.faint; Layout.fillWidth: true; visible: sub !== "" }
        }
    }

    // -------------------------------------------------------- compact (panel)

    compactRepresentation: MouseArea {
        Layout.minimumWidth: compactRow.implicitWidth + Kirigami.Units.smallSpacing * 2
        onClicked: root.expanded = !root.expanded

        RowLayout {
            id: compactRow
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing
            // Only the limit can actually stop work, so only it gets a colour.
            Dot {
                visible: root.sessionLimit !== null && root.sessionLimit.severity !== "normal"
                fill: root.sessionLimit ? root.severityColor(root.sessionLimit.severity) : root.accent
            }
            PlasmaComponents.Label {
                text: {
                    var cost = root.usage && root.usage.block ? root.fmtCost(root.usage.block.cost) : "--";
                    if (root.cfgBool("showLimitInPanel", true) && root.sessionLimit)
                        return cost + " · " + Math.round(root.sessionLimit.pct) + "%";
                    return cost;
                }
            }
        }
    }

    // ---------------------------------------------------------- full (desktop)

    fullRepresentation: Item {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 17
        Layout.minimumHeight: Kirigami.Units.gridUnit * 14
        Layout.preferredWidth: Kirigami.Units.gridUnit * 23
        Layout.preferredHeight: Kirigami.Units.gridUnit * 40

        PlasmaComponents.Label {
            anchors.centerIn: parent
            width: parent.width - Kirigami.Units.largeSpacing * 2
            visible: root.errorText !== "" && root.usage === null
            text: root.errorText
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            opacity: 0.7
        }

        PlasmaComponents.Label {
            anchors.centerIn: parent
            visible: root.loading && root.usage === null && root.errorText === ""
            text: i18n("Reading usage…")
            opacity: 0.6
        }

        ColumnLayout {
            id: contentColumn
            anchors.fill: parent
            anchors.margins: root.pad
            spacing: root.pad
            visible: root.usage !== null

            // ===== header =============================================
            RowLayout {
                Layout.fillWidth: true
                spacing: root.gap

                Kirigami.Icon {
                    source: "utilities-system-monitor"
                    implicitWidth: Kirigami.Units.iconSizes.small
                    implicitHeight: Kirigami.Units.iconSizes.small
                }
                PlasmaComponents.Label {
                    text: i18n("Claude Code")
                    color: root.ink; font.pointSize: root.fsBody; font.weight: Font.DemiBold
                }
                Muted {
                    Layout.fillWidth: true
                    text: root.limits && root.limits.plan ? root.limits.plan : ""
                    font.pointSize: root.fsTiny
                }
                Rectangle {
                    readonly property bool active: !!(root.usage && root.usage.block && root.usage.block.active)
                    radius: height / 2
                    color: active ? Qt.alpha(root.good, 0.18) : root.card
                    implicitHeight: pillRow.implicitHeight + root.gap
                    implicitWidth: pillRow.implicitWidth + root.pad * 1.5
                    RowLayout {
                        id: pillRow
                        anchors.centerIn: parent
                        spacing: root.gap
                        Dot { fill: parent.parent.active ? root.good : Qt.alpha(root.ink, 0.35) }
                        PlasmaComponents.Label {
                            text: parent.parent.active
                                  ? i18n("Block · %1 left", root.fmtMins(root.usage.block.remaining_min))
                                  : i18n("Idle")
                            color: root.ink; font.pointSize: root.fsTiny; font.weight: Font.DemiBold
                        }
                    }
                }
            }

            // ===== plan limits =======================================
            ColumnLayout {
                Layout.fillWidth: true
                spacing: root.gap
                visible: root.showLimits && root.sessionLimit !== null

                RowLayout {
                    Layout.fillWidth: true
                    spacing: root.pad
                    ColumnLayout {
                        spacing: 0
                        SectionTitle { text: i18n("Session limit") }
                        RowLayout {
                            spacing: root.gap
                            PlasmaComponents.Label {
                                text: root.sessionLimit ? Math.round(root.sessionLimit.pct) + "%" : "--"
                                color: root.ink; font.pointSize: root.fsHero; font.weight: Font.DemiBold
                            }
                            Kirigami.Icon {
                                visible: root.sessionLimit !== null && root.sessionLimit.severity !== "normal"
                                source: root.sessionLimit && root.sessionLimit.severity === "critical" ? "dialog-error" : "dialog-warning"
                                implicitWidth: Kirigami.Units.iconSizes.smallMedium; implicitHeight: implicitWidth
                                Layout.alignment: Qt.AlignVCenter
                            }
                        }
                    }
                    Item { Layout.fillWidth: true }
                    ColumnLayout {
                        Layout.alignment: Qt.AlignBottom
                        spacing: 0
                        Muted {
                            Layout.alignment: Qt.AlignRight
                            horizontalAlignment: Text.AlignRight
                            text: root.sessionLimit && root.sessionLimit.resets_in_min !== null
                                  ? i18n("resets in %1", root.fmtUntil(root.sessionLimit.resets_in_min)) : ""
                            opacity: 0.85
                        }
                        Muted {
                            Layout.alignment: Qt.AlignRight
                            horizontalAlignment: Text.AlignRight
                            font.pointSize: root.fsTiny
                            text: root.sessionLimit
                                  ? (root.severityWord(root.sessionLimit.severity) !== ""
                                     ? root.severityWord(root.sessionLimit.severity) + " · " : "")
                                    + i18n("at %1", root.sessionLimit.resets_at_local || "--")
                                  : ""
                        }
                    }
                }

                Meter {
                    thickness: 8
                    frac: root.sessionLimit ? root.sessionLimit.pct / 100 : 0
                    fill: root.sessionLimit ? root.severityColor(root.sessionLimit.severity) : root.accent
                    pace: root.elapsedFrac(root.sessionLimit)
                    HoverHandler { id: sessHover }
                    QQC.ToolTip.visible: sessHover.hovered && root.sessionLimit !== null
                    QQC.ToolTip.delay: 200
                    QQC.ToolTip.text: root.sessionLimit
                        ? root.paceText(root.sessionLimit) + "\n" + i18n("The tick marks time elapsed in the window")
                        : ""
                }

                Repeater {
                    model: root.secondaryLimits
                    delegate: RowLayout {
                        id: limRow
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.topMargin: 2
                        spacing: root.gap * 2
                        PlasmaComponents.Label {
                            text: limRow.modelData.label
                            color: root.ink; opacity: root.muted; font.pointSize: root.fsSmall
                            elide: Text.ElideRight
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 5.5
                        }
                        Meter {
                            frac: limRow.modelData.pct / 100
                            fill: root.severityColor(limRow.modelData.severity)
                            pace: root.elapsedFrac(limRow.modelData)
                            HoverHandler { id: limHover }
                            QQC.ToolTip.visible: limHover.hovered
                            QQC.ToolTip.delay: 200
                            QQC.ToolTip.text: root.paceText(limRow.modelData)
                        }
                        PlasmaComponents.Label {
                            text: Math.round(limRow.modelData.pct) + "%"
                            color: root.ink; font.pointSize: root.fsSmall; font.weight: Font.DemiBold
                            font.features: { "tnum": 1 }
                            horizontalAlignment: Text.AlignRight
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 2
                        }
                        Muted {
                            text: root.limitReset(limRow.modelData)
                            font.pointSize: root.fsTiny
                            horizontalAlignment: Text.AlignRight
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 3.5
                        }
                    }
                }

                Muted {
                    Layout.fillWidth: true
                    font.pointSize: root.fsTiny; opacity: root.faint
                    visible: root.creditsText !== "" || (root.limits && root.limits.stale)
                    text: [root.creditsText,
                           root.limits && root.limits.stale
                               ? i18n("cached %1", root.fmtAgo(Math.floor((root.limits.age_sec || 0) / 60)))
                                 + (root.limits.reason ? " · " + root.limits.reason : "")
                               : ""].filter(function (s) { return s !== ""; }).join(" · ")
                }
            }

            Muted {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                visible: root.showLimits && root.usage !== null && root.sessionLimit === null
                text: root.limits && root.limits.reason
                      ? i18n("Plan limits unavailable — %1", root.limits.reason)
                      : i18n("Plan limits unavailable")
            }

            // ===== current block =====================================
            ColumnLayout {
                Layout.fillWidth: true
                spacing: root.gap

                RowLayout {
                    Layout.fillWidth: true
                    SectionTitle { text: i18n("Current %1h block", root.usage ? root.usage.block_hours : 5) }
                    Item { Layout.fillWidth: true }
                    Muted {
                        visible: root.blockLimit > 0
                        font.pointSize: root.fsTiny
                        text: root.usage ? i18n("%1% of %2 budget",
                                                Math.round(root.usage.block.cost / root.blockLimit * 100),
                                                root.fmtCost(root.blockLimit)) : ""
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: root.gap
                    visible: !!(root.usage && root.usage.block && root.usage.block.active)
                    StatTile {
                        label: i18n("Spend")
                        value: root.usage ? root.fmtCost(root.usage.block.cost) : "--"
                        sub: root.usage ? i18n("%1 msg · %2 tok", root.usage.block.messages,
                                               root.fmtTokens(root.usage.block.tokens)) : ""
                    }
                    StatTile {
                        label: i18n("Burn rate")
                        value: root.usage ? i18n("%1/h", root.fmtCost(root.usage.block.burn_cost_per_hour)) : "--"
                        sub: root.usage ? i18n("%1 tok/min", root.fmtTokens(root.usage.block.burn_tokens_per_min)) : ""
                    }
                    StatTile {
                        label: i18n("Projected")
                        value: root.usage ? root.fmtCost(root.usage.block.projected_cost) : "--"
                        sub: root.usage && root.usage.block.end
                             ? i18n("by %1", root.usage.block.end.split("T")[1].substring(0, 5)) : ""
                    }
                }
                Muted {
                    visible: !!(root.usage && root.usage.block && !root.usage.block.active)
                    text: i18n("No requests in the last %1 hours", root.usage ? root.usage.block_hours : 5)
                }
                Rectangle {   // block budget meter, only when one is configured
                    visible: root.blockLimit > 0 && !!root.usage
                    Layout.fillWidth: true
                    implicitHeight: 4; radius: 2
                    color: Qt.alpha(root.accent, 0.22)
                    Rectangle {
                        readonly property real f: root.usage && root.blockLimit > 0 ? root.usage.block.cost / root.blockLimit : 0
                        width: parent.width * Math.min(1, f); height: parent.height; radius: 2
                        color: f >= 1 ? root.critical : f >= 0.9 ? root.warning : root.accent
                    }
                }
            }

            // ===== period totals =====================================
            RowLayout {
                Layout.fillWidth: true
                spacing: 0
                Repeater {
                    model: root.usage ? [
                        { key: i18n("Today"), val: root.usage.today.cost,
                          pct: root.budgetFrac(root.usage.today.cost, root.dailyLimit) },
                        { key: i18n("7 days"), val: root.usage.week.cost,
                          pct: root.budgetFrac(root.usage.week.cost, root.weeklyLimit) },
                        { key: i18n("30 days"), val: root.usage.month.cost, pct: -1 },
                        { key: i18n("All time"), val: root.usage.total.cost, pct: -1 }
                    ] : []

                    delegate: ColumnLayout {
                        id: period
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        spacing: 0
                        RowLayout {
                            spacing: root.gap
                            PlasmaComponents.Label {
                                text: root.fmtCost(period.modelData.val)
                                color: root.ink; font.pointSize: root.fsValue; font.weight: Font.DemiBold
                            }
                            Dot {
                                visible: period.modelData.pct >= 0.9
                                fill: period.modelData.pct >= 1 ? root.critical : root.warning
                            }
                        }
                        Muted {
                            Layout.fillWidth: true
                            font.pointSize: root.fsTiny
                            text: period.modelData.pct >= 0
                                  ? i18n("%1 · %2% of budget", period.modelData.key, Math.round(period.modelData.pct * 100))
                                  : period.modelData.key
                        }
                    }
                }
            }

            // ===== daily spend =======================================
            ColumnLayout {
                Layout.fillWidth: true
                spacing: root.gap
                visible: root.cfgBool("showChart", true) && root.daily.length > 0

                RowLayout {
                    Layout.fillWidth: true
                    spacing: root.gap
                    SectionTitle { text: i18n("Daily spend") }
                    Item { Layout.fillWidth: true }
                    Repeater {
                        model: root.familiesInChart
                        delegate: RowLayout {
                            required property string modelData
                            spacing: root.gap
                            Dot { fill: root.familyColors[modelData] }
                            Muted { text: root.familyNames[modelData]; opacity: 0.85 }
                            Item { implicitWidth: root.gap }
                        }
                    }
                }

                Item {
                    id: chart
                    Layout.fillWidth: true
                    readonly property real valueBand: Kirigami.Units.gridUnit * 0.9
                    readonly property real labelBand: Kirigami.Units.gridUnit * 0.9
                    readonly property real plotH: Kirigami.Units.gridUnit * 3.6
                    readonly property int maxIdx: {
                        var m = -1, mi = -1;
                        for (var i = 0; i < root.daily.length; i++)
                            if (root.daily[i].cost > m) { m = root.daily[i].cost; mi = i; }
                        return mi;
                    }
                    implicitHeight: valueBand + plotH + labelBand

                    Rectangle {   // baseline
                        width: parent.width; height: 1
                        y: chart.valueBand + chart.plotH
                        color: root.hairline
                    }

                    Row {
                        anchors { left: parent.left; right: parent.right; top: parent.top }
                        Repeater {
                            model: root.daily
                            delegate: Item {
                                id: dayCol
                                required property var modelData
                                required property int index
                                readonly property bool isToday: index === root.daily.length - 1
                                readonly property real slotW: chart.width / Math.max(1, root.daily.length)
                                readonly property real barW: Math.min(18, slotW * 0.62)
                                readonly property real scale: root.dailyMax > 0 ? chart.plotH / root.dailyMax : 0
                                // Stack bottom-up in fixed family order, 2px surface gap between.
                                readonly property var segs: {
                                    var out = [], y = 0;
                                    var fams = root.familiesInChart;
                                    for (var i = 0; i < fams.length; i++) {
                                        var v = modelData.families[fams[i]] || 0;
                                        if (v <= 0) continue;
                                        var h = Math.max(2, v * scale);
                                        if (out.length > 0) y += 2;
                                        out.push({ fam: fams[i], y: y, h: h });
                                        y += h;
                                    }
                                    return out;
                                }
                                readonly property real stackH: segs.length ? segs[segs.length - 1].y + segs[segs.length - 1].h : 0
                                width: slotW
                                height: chart.implicitHeight

                                Rectangle {   // hover column
                                    x: 1; width: parent.width - 2
                                    y: chart.valueBand; height: chart.plotH
                                    radius: Kirigami.Units.cornerRadius
                                    color: Qt.alpha(root.ink, 0.06)
                                    visible: colHover.hovered
                                }
                                Repeater {
                                    model: dayCol.segs
                                    delegate: Seg {
                                        required property var modelData
                                        required property int index
                                        width: dayCol.barW; height: modelData.h
                                        x: (dayCol.width - width) / 2
                                        y: chart.valueBand + chart.plotH - modelData.y - modelData.h
                                        fill: root.familyColors[modelData.fam]
                                        roundTop: index === dayCol.segs.length - 1
                                    }
                                }
                                PlasmaComponents.Label {   // label the biggest day and today only
                                    visible: (dayCol.isToday || dayCol.index === chart.maxIdx) && dayCol.modelData.cost > 0
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: chart.valueBand + chart.plotH - dayCol.stackH - height - 1
                                    text: root.fmtCost(dayCol.modelData.cost)
                                    color: root.ink; opacity: 0.85; font.pointSize: root.fsTiny
                                    font.weight: Font.DemiBold
                                }
                                PlasmaComponents.Label {   // sparse x labels
                                    visible: dayCol.index === 0 || dayCol.index === 7 || dayCol.isToday
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: chart.valueBand + chart.plotH + 2
                                    text: dayCol.isToday ? i18n("Today") : dayCol.modelData.label
                                    color: root.ink; opacity: root.faint; font.pointSize: root.fsTiny
                                }
                                HoverHandler { id: colHover }
                                QQC.ToolTip.visible: colHover.hovered
                                QQC.ToolTip.delay: 0
                                QQC.ToolTip.text: {
                                    var t = dayCol.modelData.weekday + " " + dayCol.modelData.label
                                            + " — " + root.fmtCost(dayCol.modelData.cost);
                                    var fams = root.familiesInChart;
                                    for (var i = 0; i < fams.length; i++) {
                                        var v = dayCol.modelData.families[fams[i]] || 0;
                                        if (v > 0) t += "\n" + root.familyNames[fams[i]] + " " + root.fmtCost(v);
                                    }
                                    return t;
                                }
                            }
                        }
                    }

                    Muted {
                        anchors.centerIn: parent
                        visible: root.dailyMax === 0
                        text: i18n("No spend in the last 14 days")
                    }
                }
            }

            // ===== by model ==========================================
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                visible: root.cfgBool("showModels", true) && root.modelRows.length > 0

                SectionTitle { text: i18n("By model · all time") }
                Repeater {
                    model: root.modelRows
                    delegate: RowLayout {
                        id: modelRow
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: root.gap * 1.5
                        Dot { fill: root.familyColors[modelRow.modelData.family] }
                        PlasmaComponents.Label {
                            text: modelRow.modelData.name
                            color: root.ink; font.pointSize: root.fsSmall
                            elide: Text.ElideRight
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 6.5
                        }
                        Rectangle {   // magnitude bar: neutral ink, the dot carries identity
                            Layout.fillWidth: true
                            implicitHeight: 4; radius: 2
                            color: Qt.alpha(root.ink, 0.08)
                            Rectangle {
                                width: Math.max(2, parent.width * modelRow.modelData.frac)
                                height: parent.height; radius: parent.radius
                                color: Qt.alpha(root.ink, 0.55)
                            }
                        }
                        PlasmaComponents.Label {
                            text: root.fmtCost(modelRow.modelData.cost)
                            color: root.ink; font.pointSize: root.fsSmall; font.weight: Font.DemiBold
                            font.features: { "tnum": 1 }
                            horizontalAlignment: Text.AlignRight
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 3.5
                        }
                    }
                }
            }

            // ===== recent sessions ===================================
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: Kirigami.Units.gridUnit * 4
                spacing: root.gap
                visible: root.cfgBool("showSessions", true) && root.usage && root.usage.sessions.length > 0

                RowLayout {
                    Layout.fillWidth: true
                    SectionTitle { text: i18n("Recent sessions") }
                    Item { Layout.fillWidth: true }
                    Muted {
                        text: root.usage ? i18n("%1 total", root.usage.session_count) : ""
                        font.pointSize: root.fsTiny; opacity: root.faint
                    }
                }

                QQC.ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    QQC.ScrollBar.horizontal.policy: QQC.ScrollBar.AlwaysOff

                    ListView {
                        model: root.usage ? root.usage.sessions : []
                        spacing: 0
                        delegate: Item {
                            id: sessRow
                            required property var modelData
                            required property int index
                            readonly property string place: modelData.dir
                                || String(modelData.project || "").replace(/^-/, "/").replace(/-/g, "/")
                            width: ListView.view.width
                            implicitHeight: sessGrid.implicitHeight + root.gap * 2
                            HoverHandler { id: sessHover2 }
                            Rectangle {
                                anchors.fill: parent
                                radius: Kirigami.Units.cornerRadius
                                color: Qt.alpha(root.ink, 0.06)
                                visible: sessHover2.hovered
                            }
                            Rectangle {   // hairline divider
                                visible: sessRow.index > 0
                                anchors { top: parent.top; left: parent.left; right: parent.right
                                          leftMargin: root.gap; rightMargin: root.gap }
                                height: 1; color: root.hairline
                            }
                            QQC.ToolTip.visible: sessHover2.hovered
                            QQC.ToolTip.delay: 400
                            QQC.ToolTip.text: (sessRow.modelData.cwd || sessRow.place)
                                              + "\n" + root.fmtTokens(sessRow.modelData.tokens) + " " + i18n("tokens")
                                              + (sessRow.modelData.model ? " · " + root.shortModel(sessRow.modelData.model) : "")

                            GridLayout {
                                id: sessGrid
                                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                                          leftMargin: root.gap; rightMargin: root.pad }
                                columns: 3
                                columnSpacing: root.gap * 1.5
                                rowSpacing: 1

                                Dot {   // active in the current block: status, so labelled in the meta line too
                                    fill: sessRow.modelData.active ? root.good : Qt.alpha(root.ink, 0.25)
                                    Layout.rowSpan: 2
                                    Layout.alignment: Qt.AlignTop
                                    Layout.topMargin: 5
                                }
                                PlasmaComponents.Label {
                                    Layout.fillWidth: true
                                    text: sessRow.modelData.title || sessRow.place
                                    color: root.ink; font.pointSize: root.fsBody
                                    elide: Text.ElideRight
                                }
                                PlasmaComponents.Label {
                                    Layout.alignment: Qt.AlignRight
                                    text: root.fmtCost(sessRow.modelData.cost)
                                    color: root.ink; font.pointSize: root.fsBody; font.weight: Font.DemiBold
                                    font.features: { "tnum": 1 }
                                }
                                Muted {
                                    Layout.fillWidth: true
                                    font.pointSize: root.fsTiny
                                    text: [sessRow.modelData.active ? i18n("active") : "",
                                           sessRow.modelData.title ? sessRow.place : "",
                                           sessRow.modelData.model ? root.shortModel(sessRow.modelData.model) : "",
                                           sessRow.modelData.ago_min !== undefined ? root.fmtAgo(sessRow.modelData.ago_min) : ""]
                                          .filter(function (s) { return s !== ""; }).join(" · ")
                                }
                                Rectangle {   // relative cost
                                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 3
                                    implicitHeight: 3; radius: 1.5
                                    color: Qt.alpha(root.ink, 0.1)
                                    Rectangle {
                                        height: parent.height; radius: parent.radius
                                        width: root.sessionMax > 0 ? Math.max(2, parent.width * sessRow.modelData.cost / root.sessionMax) : 0
                                        color: Qt.alpha(root.ink, 0.55)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Item {
                Layout.fillHeight: true
                visible: !(root.cfgBool("showSessions", true) && root.usage && root.usage.sessions.length > 0)
            }

            // ===== footer ============================================
            RowLayout {
                Layout.fillWidth: true
                Muted {
                    Layout.fillWidth: true
                    font.pointSize: root.fsTiny; opacity: root.faint
                    text: root.errorText !== "" ? "⚠ " + root.errorText : i18n("Costs at API list prices")
                }
                Muted {
                    font.pointSize: root.fsTiny; opacity: root.faint
                    text: root.usage ? i18n("updated %1", root.usage.generated.split("T")[1].substring(0, 5)) : ""
                }
            }
        }
    }

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Refresh now")
            icon.name: "view-refresh"
            onTriggered: executable.refresh()
        }
    ]
}
