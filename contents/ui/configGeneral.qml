import QtQuick
import QtQuick.Controls as QQC
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    property alias cfg_scriptPath: scriptPath.text
    property alias cfg_refreshInterval: refreshInterval.value
    property alias cfg_blockCostLimit: blockCostLimit.value
    property alias cfg_dailyCostLimit: dailyCostLimit.value
    property alias cfg_weeklyCostLimit: weeklyCostLimit.value
    property alias cfg_showLimits: showLimits.checked
    property alias cfg_showLimitInPanel: showLimitInPanel.checked
    property alias cfg_showChart: showChart.checked
    property alias cfg_showModels: showModels.checked
    property alias cfg_showSessions: showSessions.checked

    QQC.TextField {
        id: scriptPath
        Kirigami.FormData.label: i18n("Collector command:")
        Layout.minimumWidth: Kirigami.Units.gridUnit * 16
    }

    QQC.SpinBox {
        id: refreshInterval
        Kirigami.FormData.label: i18n("Refresh every:")
        from: 10
        to: 3600
        stepSize: 10
        textFromValue: function (value) { return i18np("%1 second", "%1 seconds", value); }
        valueFromText: function (text) { return parseInt(text) || 60; }
    }

    Item { Kirigami.FormData.isSection: true }

    QQC.SpinBox {
        id: blockCostLimit
        Kirigami.FormData.label: i18n("Block budget:")
        from: 0
        to: 100000
        stepSize: 100
        textFromValue: function (value) {
            return value === 0 ? i18n("none (track elapsed time)")
                               : "$" + (value / 100).toFixed(2);
        }
        valueFromText: function (text) {
            return Math.round(parseFloat(text.replace("$", "")) * 100) || 0;
        }
    }

    QQC.SpinBox {
        id: dailyCostLimit
        Kirigami.FormData.label: i18n("Daily budget:")
        from: 0
        to: 1000000
        stepSize: 100
        textFromValue: function (value) {
            return value === 0 ? i18n("none") : "$" + (value / 100).toFixed(2);
        }
        valueFromText: function (text) {
            return Math.round(parseFloat(text.replace("$", "")) * 100) || 0;
        }
    }

    QQC.SpinBox {
        id: weeklyCostLimit
        Kirigami.FormData.label: i18n("Weekly budget:")
        from: 0
        to: 1000000
        stepSize: 500
        textFromValue: function (value) {
            return value === 0 ? i18n("none") : "$" + (value / 100).toFixed(2);
        }
        valueFromText: function (text) {
            return Math.round(parseFloat(text.replace("$", "")) * 100) || 0;
        }
    }

    Item { Kirigami.FormData.isSection: true }

    QQC.CheckBox {
        id: showLimits
        Kirigami.FormData.label: i18n("Show:")
        text: i18n("Plan limits (session / weekly)")
    }

    QQC.CheckBox {
        id: showLimitInPanel
        text: i18n("Session limit % in the panel")
        enabled: showLimits.checked
    }

    QQC.CheckBox {
        id: showChart
        text: i18n("Daily spend chart (14 days)")
    }

    QQC.CheckBox {
        id: showModels
        text: i18n("Per-model breakdown")
    }

    QQC.CheckBox {
        id: showSessions
        text: i18n("Recent sessions")
    }
}
