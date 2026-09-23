// A stand-in window for renders and the artwork: an illustrated app of the
// given kind (code, terminal, monitor, browser, notes, music, chat, mail,
// game, files, photos, calendar), drawn in the palette of the theme the apps
// follow (FakeSystem.appPalette). Proportional, so it reads as a thumbnail
// on the map and as a window in front.

import QtQuick

Item {
  id: app

  property string kind: ""
  readonly property var p: FakeSystem.appPalette || ({
    dark: true, bg: "#1a1b26", surface: "#16161e", raised: "#24283b", fg: "#c0caf5", dim: "#565f89",
    faint: "#3b4261", accent: "#7aa2f7", colors: ["#7aa2f7", "#bb9af7", "#9ece6a", "#7dcfff", "#ff9e64", "#f7768e", "#e0af68"]
  })
  readonly property real u: Math.max(0.2, Math.min(width / 1000, height / 620))

  function color(i) { return app.p.colors[((i % app.p.colors.length) + app.p.colors.length) % app.p.colors.length] }
  // A stable pseudo-random number in [0, 1) for a seed.
  function noise(seed) { const x = Math.sin(seed * 12.9898 + 78.233) * 43758.5453; return x - Math.floor(x) }

  clip: true

  Rectangle {
    anchors.fill: parent
    color: app.kind === "browser" || app.kind === "notes" || app.kind === "mail" ? app.p.raised : app.p.bg
  }

  // ---------------------------------------------------------------- code
  Item {
    anchors.fill: parent
    visible: app.kind === "code"

    Rectangle { width: parent.width * 0.2; height: parent.height; color: app.p.surface }
    Column {
      x: parent.width * 0.02; y: parent.height * 0.08; spacing: parent.height * 0.028
      Repeater {
        model: 14
        delegate: Rectangle {
          required property int index
          x: (index % 4 === 1 || index % 4 === 2) ? app.width * 0.015 : 0
          width: app.width * (0.08 + app.noise(index + 3) * 0.07); height: Math.max(1, app.height * 0.016); radius: height / 2
          color: index === 5 ? app.p.accent : app.p.dim; opacity: index === 5 ? 0.9 : 0.6
        }
      }
    }
    Rectangle { x: parent.width * 0.2; width: parent.width * 0.8; height: parent.height * 0.055; color: app.p.surface }
    Rectangle { x: parent.width * 0.2; width: parent.width * 0.16; height: parent.height * 0.055; color: app.p.bg
      Rectangle { anchors.centerIn: parent; width: parent.width * 0.6; height: Math.max(1, app.height * 0.014); radius: height / 2; color: app.p.fg; opacity: 0.7 }
      Rectangle { width: parent.width; height: Math.max(1, 2 * app.u); color: app.p.accent }
    }
    Column {
      x: parent.width * 0.23; y: parent.height * 0.1; spacing: parent.height * 0.022
      Repeater {
        model: 24
        delegate: Row {
          id: codeLine
          required property int index
          readonly property int indent: [0, 1, 1, 2, 2, 2, 1, 0, 0, 1, 2, 3, 3, 2, 1, 0, 1, 1, 2, 2, 1, 0, 0, 1][index]
          spacing: app.width * 0.008
          Rectangle { width: app.width * 0.018; height: Math.max(1, app.height * 0.014); radius: height / 2; color: app.p.faint }
          Item { width: codeLine.indent * app.width * 0.03; height: 1 }
          Repeater {
            model: codeLine.index % 8 === 7 ? 0 : 1 + Math.floor(app.noise(codeLine.index) * 4)
            delegate: Rectangle {
              required property int index
              width: app.width * (0.03 + app.noise(codeLine.index * 7 + index) * 0.09); height: Math.max(1, app.height * 0.014); radius: height / 2
              color: codeLine.index % 6 === 0 ? app.p.dim : app.color(codeLine.index * 3 + index)
              opacity: codeLine.index % 6 === 0 ? 0.7 : 0.85
            }
          }
        }
      }
    }
  }

  // ---------------------------------------------------------------- terminal
  Column {
    visible: app.kind === "terminal"
    x: parent.width * 0.04; y: parent.height * 0.06; spacing: parent.height * 0.03
    Repeater {
      model: 15
      delegate: Row {
        id: termLine
        required property int index
        readonly property bool prompt: index % 5 === 0
        spacing: app.width * 0.012
        Rectangle { visible: termLine.prompt; width: app.width * 0.02; height: Math.max(1, app.height * 0.02); radius: height / 3; color: app.color(2) }
        Rectangle { visible: termLine.prompt; width: app.width * 0.1; height: Math.max(1, app.height * 0.02); radius: height / 2; color: app.color(0); opacity: 0.9 }
        Rectangle {
          width: app.width * (termLine.prompt ? 0.22 : 0.25 + app.noise(termLine.index + 11) * 0.5); height: Math.max(1, app.height * 0.02); radius: height / 2
          color: termLine.prompt ? app.p.fg : (termLine.index % 5 === 3 ? app.color(termLine.index) : app.p.dim)
          opacity: termLine.prompt ? 0.9 : 0.75
        }
      }
    }
    Row {
      spacing: app.width * 0.012
      Rectangle { width: app.width * 0.02; height: Math.max(1, app.height * 0.02); radius: height / 3; color: app.color(2) }
      Rectangle { width: app.width * 0.014; height: app.height * 0.034; color: app.p.fg; opacity: 0.85 }
    }
  }

  // ---------------------------------------------------------------- monitor
  Item {
    anchors.fill: parent
    anchors.margins: parent.width * 0.02
    visible: app.kind === "monitor"

    Rectangle {
      id: cpu
      width: parent.width; height: parent.height * 0.42; radius: 6 * app.u
      color: "transparent"; border.width: Math.max(1, 1.5 * app.u); border.color: app.color(2)
      Row {
        id: bars
        anchors.bottom: parent.bottom; anchors.bottomMargin: parent.height * 0.08; x: parent.width * 0.03
        height: cpu.height * 0.75
        spacing: parent.width * 0.004
        Repeater {
          model: 60
          delegate: Rectangle {
            required property int index
            readonly property real level: 0.2 + 0.6 * Math.abs(Math.sin(index * 0.23)) * (0.6 + 0.4 * app.noise(index))
            y: bars.height - height
            width: cpu.width * 0.011; height: cpu.height * 0.75 * level; radius: width / 3
            color: level > 0.62 ? app.color(5) : (level > 0.42 ? app.color(6) : app.color(2))
          }
        }
      }
    }
    Rectangle {
      id: memory
      y: parent.height * 0.46; width: parent.width * 0.38; height: parent.height * 0.54; radius: 6 * app.u
      color: "transparent"; border.width: Math.max(1, 1.5 * app.u); border.color: app.color(1)
      Column {
        x: parent.width * 0.08; y: parent.height * 0.14; spacing: parent.height * 0.1
        Repeater {
          model: 4
          delegate: Rectangle {
            required property int index
            width: memory.width * 0.84; height: memory.height * 0.07; radius: height / 2; color: app.p.faint
            Rectangle { width: parent.width * [0.72, 0.41, 0.23, 0.58][parent.index]; height: parent.height; radius: height / 2; color: app.color(parent.index + 1) }
          }
        }
      }
    }
    Rectangle {
      x: parent.width * 0.4; y: parent.height * 0.46; width: parent.width * 0.6; height: parent.height * 0.54; radius: 6 * app.u
      color: "transparent"; border.width: Math.max(1, 1.5 * app.u); border.color: app.color(0)
      Column {
        x: parent.width * 0.05; y: parent.height * 0.1; spacing: parent.height * 0.06
        Repeater {
          model: 9
          delegate: Row {
            id: process
            required property int index
            spacing: app.width * 0.02
            Rectangle { width: app.width * 0.04; height: Math.max(1, app.height * 0.016); radius: height / 2; color: app.p.dim }
            Rectangle { width: app.width * (0.12 + app.noise(process.index + 40) * 0.12); height: Math.max(1, app.height * 0.016); radius: height / 2; color: process.index === 0 ? app.p.accent : app.p.fg; opacity: 0.8 }
            Rectangle { width: app.width * 0.05; height: Math.max(1, app.height * 0.016); radius: height / 2; color: app.color(process.index + 2); opacity: 0.8 }
          }
        }
      }
    }
  }

  // ---------------------------------------------------------------- browser
  Item {
    anchors.fill: parent
    visible: app.kind === "browser"

    Rectangle { width: parent.width; height: parent.height * 0.075; color: app.p.surface
      Rectangle { x: parent.width * 0.2; anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.6; height: parent.height * 0.56; radius: height / 2; color: app.p.bg
        Rectangle { x: parent.height * 0.6; anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.3; height: parent.height * 0.3; radius: height / 2; color: app.p.dim; opacity: 0.7 }
      }
      Row { x: parent.width * 0.02; anchors.verticalCenter: parent.verticalCenter; spacing: parent.height * 0.3
        Repeater { model: 3; delegate: Rectangle { width: app.height * 0.022; height: width; radius: width / 2; color: app.p.dim; opacity: 0.6 } }
      }
    }
    Rectangle {
      x: parent.width * 0.06; y: parent.height * 0.12; width: parent.width * 0.88; height: parent.height * 0.4; radius: 10 * app.u
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0; color: app.color(1) }
        GradientStop { position: 1; color: app.color(0) }
      }
      Rectangle { x: parent.width * 0.06; y: parent.height * 0.3; width: parent.width * 0.42; height: parent.height * 0.12; radius: height / 3; color: "#ffffff"; opacity: 0.95 }
      Rectangle { x: parent.width * 0.06; y: parent.height * 0.5; width: parent.width * 0.3; height: parent.height * 0.06; radius: height / 2; color: "#ffffff"; opacity: 0.7 }
      Rectangle { x: parent.width * 0.06; y: parent.height * 0.68; width: parent.width * 0.14; height: parent.height * 0.13; radius: height / 2; color: "#ffffff" }
      Rectangle { x: parent.width * 0.64; y: parent.height * 0.18; width: parent.height * 0.64; height: width; radius: width / 2; color: "#ffffff"; opacity: 0.18 }
    }
    Row {
      x: parent.width * 0.06; y: parent.height * 0.57; spacing: parent.width * 0.03
      Repeater {
        model: 3
        delegate: Column {
          id: card
          required property int index
          spacing: app.height * 0.022
          Rectangle { width: app.width * 0.273; height: app.height * 0.2; radius: 8 * app.u; color: app.color(card.index + 2); opacity: 0.85 }
          Rectangle { width: app.width * 0.2; height: Math.max(1, app.height * 0.022); radius: height / 2; color: app.p.fg; opacity: 0.85 }
          Rectangle { width: app.width * 0.25; height: Math.max(1, app.height * 0.016); radius: height / 2; color: app.p.dim; opacity: 0.7 }
          Rectangle { width: app.width * 0.16; height: Math.max(1, app.height * 0.016); radius: height / 2; color: app.p.dim; opacity: 0.7 }
        }
      }
    }
  }

  // ---------------------------------------------------------------- notes
  Column {
    visible: app.kind === "notes"
    x: parent.width * 0.1; y: parent.height * 0.1; spacing: parent.height * 0.035
    Rectangle { width: app.width * 0.45; height: app.height * 0.05; radius: height / 4; color: app.p.fg }
    Rectangle { width: app.width * 0.18; height: Math.max(1, app.height * 0.018); radius: height / 2; color: app.p.dim; opacity: 0.8 }
    Item { width: 1; height: app.height * 0.02 }
    Repeater {
      model: 7
      delegate: Row {
        id: todo
        required property int index
        spacing: app.width * 0.02
        Rectangle {
          width: app.height * 0.032; height: width; radius: width * 0.25
          color: todo.index < 3 ? app.p.accent : "transparent"; border.width: Math.max(1, 1.5 * app.u); border.color: todo.index < 3 ? app.p.accent : app.p.dim
        }
        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: app.width * (0.25 + app.noise(todo.index + 21) * 0.35); height: Math.max(1, app.height * 0.02); radius: height / 2; color: todo.index < 3 ? app.p.dim : app.p.fg; opacity: todo.index < 3 ? 0.6 : 0.85 }
      }
    }
    Item { width: 1; height: app.height * 0.02 }
    Repeater {
      model: 4
      delegate: Rectangle { required property int index; width: app.width * (0.55 + app.noise(index + 60) * 0.25); height: Math.max(1, app.height * 0.018); radius: height / 2; color: app.p.dim; opacity: 0.7 }
    }
  }

  // ---------------------------------------------------------------- music
  Item {
    anchors.fill: parent
    visible: app.kind === "music"

    Rectangle {
      id: cover
      x: parent.width * 0.05; y: parent.height * 0.08; width: Math.min(parent.width * 0.38, parent.height * 0.62); height: width; radius: 10 * app.u
      gradient: Gradient {
        GradientStop { position: 0; color: app.color(4) }
        GradientStop { position: 0.55; color: app.color(5) }
        GradientStop { position: 1; color: app.color(1) }
      }
      Rectangle { anchors.centerIn: parent; width: parent.width * 0.62; height: width; radius: width / 2; color: "transparent"; border.width: parent.width * 0.05; border.color: "#ffffff"; opacity: 0.35 }
      Rectangle { anchors.centerIn: parent; width: parent.width * 0.16; height: width; radius: width / 2; color: "#ffffff"; opacity: 0.55 }
    }
    Column {
      x: cover.x + cover.width + parent.width * 0.05; y: cover.y + cover.height * 0.05; spacing: app.height * 0.03
      Rectangle { width: app.width * 0.3; height: app.height * 0.05; radius: height / 4; color: app.p.fg }
      Rectangle { width: app.width * 0.18; height: Math.max(1, app.height * 0.022); radius: height / 2; color: app.p.dim }
      Item { width: 1; height: app.height * 0.02 }
      Repeater {
        model: 8
        delegate: Row {
          id: track
          required property int index
          spacing: app.width * 0.02
          Rectangle { width: app.width * 0.02; height: Math.max(1, app.height * 0.018); radius: height / 2; color: track.index === 2 ? app.p.accent : app.p.dim }
          Rectangle { width: app.width * (0.16 + app.noise(track.index + 80) * 0.18); height: Math.max(1, app.height * 0.018); radius: height / 2; color: track.index === 2 ? app.p.accent : app.p.fg; opacity: 0.85 }
        }
      }
    }
    Rectangle {
      width: parent.width; height: parent.height * 0.14; anchors.bottom: parent.bottom; color: app.p.surface
      Rectangle { anchors.centerIn: parent; anchors.verticalCenterOffset: -parent.height * 0.12; width: parent.height * 0.42; height: width; radius: width / 2; color: app.p.fg }
      Rectangle { x: parent.width * 0.2; y: parent.height * 0.78; width: parent.width * 0.6; height: Math.max(1, parent.height * 0.06); radius: height / 2; color: app.p.faint
        Rectangle { width: parent.width * 0.38; height: parent.height; radius: height / 2; color: app.p.accent }
      }
    }
  }

  // ---------------------------------------------------------------- chat
  Item {
    anchors.fill: parent
    visible: app.kind === "chat"

    Rectangle { width: parent.width * 0.26; height: parent.height; color: app.p.surface
      Column {
        x: parent.width * 0.1; y: parent.height * 0.06; spacing: app.height * 0.04
        Repeater {
          model: 9
          delegate: Rectangle {
            required property int index
            x: -app.width * 0.015
            width: app.width * 0.23; height: app.height * 0.045; radius: height / 3
            color: index === 1 ? app.p.accent : "transparent"; opacity: index === 1 ? 0.25 : 1
            Rectangle { x: app.width * 0.015; anchors.verticalCenter: parent.verticalCenter; width: app.width * (0.08 + app.noise(parent.index + 90) * 0.07); height: Math.max(1, app.height * 0.016); radius: height / 2; color: app.p.fg; opacity: parent.index === 1 ? 1 : 0.6 }
          }
        }
      }
    }
    Column {
      x: parent.width * 0.3; y: parent.height * 0.07; spacing: app.height * 0.035
      Repeater {
        model: 6
        delegate: Row {
          id: message
          required property int index
          readonly property bool mine: index % 3 === 2
          layoutDirection: mine ? Qt.RightToLeft : Qt.LeftToRight
          width: app.width * 0.66
          spacing: app.width * 0.015
          Rectangle { width: app.height * 0.06; height: width; radius: width / 2; color: app.color(message.index + 3) }
          Rectangle {
            width: app.width * (0.2 + app.noise(message.index + 100) * 0.26); height: app.height * (0.07 + (message.index % 2) * 0.04); radius: 10 * app.u
            color: message.mine ? app.p.accent : app.p.raised
            Column {
              x: parent.width * 0.07; anchors.verticalCenter: parent.verticalCenter; spacing: app.height * 0.015
              Repeater {
                model: 1 + message.index % 2
                delegate: Rectangle { required property int index; width: app.width * (0.12 + app.noise(message.index * 3 + index) * 0.1); height: Math.max(1, app.height * 0.016); radius: height / 2; color: message.mine ? "#ffffff" : app.p.fg; opacity: 0.8 }
              }
            }
          }
        }
      }
    }
    Rectangle { x: parent.width * 0.3; y: parent.height * 0.88; width: parent.width * 0.66; height: parent.height * 0.07; radius: height / 2; color: app.p.raised
      Rectangle { x: parent.height * 0.5; anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.25; height: Math.max(1, app.height * 0.016); radius: height / 2; color: app.p.dim }
    }
  }

  // ---------------------------------------------------------------- mail
  Item {
    anchors.fill: parent
    visible: app.kind === "mail"

    Rectangle { width: parent.width * 0.36; height: parent.height; color: app.p.bg
      Column {
        y: parent.height * 0.04; width: parent.width
        Repeater {
          model: 9
          delegate: Rectangle {
            id: mailRow
            required property int index
            width: parent.width; height: app.height * 0.1
            color: index === 0 ? app.p.raised : "transparent"
            Rectangle { visible: mailRow.index < 3; x: parent.width * 0.04; anchors.verticalCenter: parent.verticalCenter; width: app.height * 0.016; height: width; radius: width / 2; color: app.p.accent }
            Rectangle { x: parent.width * 0.1; y: parent.height * 0.26; width: parent.width * (0.3 + app.noise(mailRow.index + 120) * 0.3); height: Math.max(1, app.height * 0.018); radius: height / 2; color: app.p.fg; opacity: mailRow.index < 3 ? 0.95 : 0.6 }
            Rectangle { x: parent.width * 0.1; y: parent.height * 0.6; width: parent.width * (0.5 + app.noise(mailRow.index + 140) * 0.35); height: Math.max(1, app.height * 0.014); radius: height / 2; color: app.p.dim; opacity: 0.7 }
          }
        }
      }
    }
    Column {
      x: parent.width * 0.41; y: parent.height * 0.08; spacing: app.height * 0.032
      Rectangle { width: app.width * 0.36; height: app.height * 0.045; radius: height / 4; color: app.p.fg }
      Row { spacing: app.width * 0.015
        Rectangle { width: app.height * 0.05; height: width; radius: width / 2; color: app.color(1) }
        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: app.width * 0.14; height: Math.max(1, app.height * 0.018); radius: height / 2; color: app.p.dim }
      }
      Repeater {
        model: 9
        delegate: Rectangle { required property int index; width: app.width * (index % 4 === 3 ? 0.3 : 0.5 - app.noise(index + 160) * 0.08); height: Math.max(1, app.height * 0.016); radius: height / 2; color: app.p.fg; opacity: index % 4 === 3 ? 0 : 0.55 }
      }
    }
  }

  // ---------------------------------------------------------------- game
  Item {
    anchors.fill: parent
    visible: app.kind === "game"

    Rectangle { anchors.fill: parent
      gradient: Gradient {
        GradientStop { position: 0; color: "#1b1340" }
        GradientStop { position: 0.55; color: "#b4486b" }
        GradientStop { position: 0.8; color: "#f2a65a" }
      }
    }
    Repeater {
      model: 40
      delegate: Rectangle {
        required property int index
        x: app.width * app.noise(index + 200); y: app.height * 0.45 * app.noise(index + 300)
        width: Math.max(1, app.width * 0.004 * (1 + app.noise(index + 400))); height: width; radius: width / 2; color: "#ffffff"; opacity: 0.4 + 0.5 * app.noise(index + 500)
      }
    }
    Rectangle { x: parent.width * 0.62; y: parent.height * 0.42; width: parent.height * 0.26; height: width; radius: width / 2; color: "#ffd9a0" }
    Repeater {
      model: [[0.05, 0.62, 0.62, "#3a1f4d"], [0.45, 0.55, 0.72, "#2b1740"], [0.78, 0.68, 0.5, "#3a1f4d"], [-0.1, 0.78, 0.5, "#1a0f2a"], [0.55, 0.82, 0.6, "#1a0f2a"]]
      delegate: Rectangle {
        required property var modelData
        x: app.width * modelData[0]; y: app.height * modelData[1]
        width: app.width * modelData[2] * 0.7; height: width; rotation: 45
        color: modelData[3]
      }
    }
    Rectangle { y: parent.height * 0.9; width: parent.width; height: parent.height * 0.1; color: "#120a1d" }
    Row { x: parent.width * 0.03; y: parent.height * 0.04; spacing: parent.width * 0.006
      Repeater { model: 5; delegate: Rectangle { required property int index; width: app.width * 0.022; height: width * 0.8; radius: width * 0.2; color: index < 4 ? "#ff5d73" : "#5a2a3a" } }
    }
    Rectangle { x: parent.width * 0.8; y: parent.height * 0.045; width: parent.width * 0.16; height: parent.height * 0.035; radius: height / 3; color: "#ffffff"; opacity: 0.85 }
  }

  // ---------------------------------------------------------------- files
  Item {
    anchors.fill: parent
    visible: app.kind === "files"

    Rectangle { width: parent.width * 0.2; height: parent.height; color: app.p.surface
      Column { x: parent.width * 0.12; y: parent.height * 0.06; spacing: app.height * 0.045
        Repeater { model: 7; delegate: Rectangle { required property int index; width: app.width * (0.08 + app.noise(index + 220) * 0.06); height: Math.max(1, app.height * 0.018); radius: height / 2; color: index === 2 ? app.p.accent : app.p.fg; opacity: index === 2 ? 1 : 0.6 } }
      }
    }
    Grid {
      x: parent.width * 0.25; y: parent.height * 0.08; columns: 5; columnSpacing: parent.width * 0.05; rowSpacing: parent.height * 0.07
      Repeater {
        model: 13
        delegate: Column {
          id: fileItem
          required property int index
          spacing: app.height * 0.02
          Item {
            width: app.width * 0.09; height: width * 0.78
            Rectangle { width: parent.width * 0.45; height: parent.height * 0.25; radius: height / 3; color: fileItem.index % 4 === 3 ? app.color(1) : app.color(0); opacity: 0.8 }
            Rectangle { y: parent.height * 0.12; width: parent.width; height: parent.height * 0.88; radius: parent.width * 0.08; color: fileItem.index % 4 === 3 ? app.color(1) : app.color(0) }
          }
          Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: app.width * (0.05 + app.noise(fileItem.index + 240) * 0.04); height: Math.max(1, app.height * 0.016); radius: height / 2; color: app.p.fg; opacity: 0.7 }
        }
      }
    }
  }

  // ---------------------------------------------------------------- photos
  Grid {
    visible: app.kind === "photos"
    x: parent.width * 0.03; y: parent.height * 0.05; columns: 4; spacing: parent.width * 0.012
    Repeater {
      model: 12
      delegate: Rectangle {
        required property int index
        width: app.width * 0.228; height: app.height * 0.29; radius: 6 * app.u
        gradient: Gradient {
          GradientStop { position: 0; color: Qt.hsla(app.noise(index + 260) * 0.2 + 0.52, 0.55, 0.62, 1) }
          GradientStop { position: 0.55; color: Qt.hsla(app.noise(index + 280) * 0.15 + 0.05, 0.6, 0.6, 1) }
          GradientStop { position: 1; color: Qt.hsla(app.noise(index + 290) * 0.1 + 0.3, 0.35, 0.3, 1) }
        }
        Rectangle { x: parent.width * (0.2 + app.noise(parent.index) * 0.5); y: parent.height * 0.18; width: parent.height * 0.2; height: width; radius: width / 2; color: "#fff4d6"; opacity: 0.8 }
      }
    }
  }

  // ---------------------------------------------------------------- calendar
  Item {
    anchors.fill: parent
    visible: app.kind === "calendar"

    Rectangle { x: parent.width * 0.04; y: parent.height * 0.05; width: parent.width * 0.3; height: parent.height * 0.055; radius: height / 4; color: app.p.fg }
    Grid {
      x: parent.width * 0.04; y: parent.height * 0.16; columns: 7; spacing: parent.width * 0.008
      Repeater {
        model: 35
        delegate: Rectangle {
          id: day
          required property int index
          width: app.width * 0.126; height: app.height * 0.15; radius: 4 * app.u
          color: index === 22 ? app.p.accent : app.p.raised; opacity: index === 22 ? 0.3 : 1
          Rectangle { x: parent.width * 0.08; y: parent.height * 0.1; width: parent.width * 0.14; height: Math.max(1, parent.height * 0.1); radius: height / 2; color: app.p.dim }
          Rectangle {
            visible: app.noise(day.index + 320) > 0.55
            x: parent.width * 0.08; y: parent.height * 0.42; width: parent.width * 0.84; height: parent.height * 0.24; radius: height / 3
            color: app.color(day.index); opacity: 0.85
          }
        }
      }
    }
  }
}
