/// The interface's words in English and Russian. Some have places, marked {}, for values put in them in order.
enum Str {
    case title
    case game, gameEight, gameNine, gameAmericanka
    case mode, modeComputer, modeTwoPlayers, modePractice, modeDemo
    case level, level1, level2, level3, level4, level5
    case aim, aimFull, aimShort, aimOff
    case theme, sound, languageName
    case camera, cameraOverview, cameraBehind, cameraTop
    case newGame, undoShot
    case nameYou, nameComputer, namePlayer, nameComputerN
    case shotYou, shotComputer, shotPlayer, shotComputerN, practice
    case winYou, winComputer, winPlayer, winComputerN, tableCleared
    case breakYou, breakComputer, breakPlayer, breakComputerN
    case breaking, thinking, aiming, rolling, pressNew
    case ballInHand, ballInKitchen, openTable, solids, stripes, onEight, hitLowest, anyBall
    case pocket0, pocket1, pocket2, pocket3, pocket4, pocket5
    case cueBall
    case foul, foulScratch, foulMiss, foulWrongBall, foulNoRail, foulEightEarly, foulEightWrongPocket, foulEightOnFoul
    case logPotted, logPottedMany, logNothing, logFoul, logSolids, logStripes, logBack, logWin
    case power, spin, metresPerSecond, history, noShotsYet, shots, left, toWin
    case footer, controls
    case keyMove, keyShiftMove, keyPull, keyClick, keyDragCue, keyRightDrag, keyWheel
    case helpAim, helpFineAim, helpStrike, helpClick, helpPlace, helpRotate, helpZoom, helpShoot, helpPower, helpTurn, helpSpin
    case helpCenter, helpCamera, helpGuide, helpUndo, helpNew, helpGame, helpMode, helpLevel, helpTheme, helpSound, helpLanguage
    case helpPanel, helpFullScreen, helpClose
    case rules, rulesEight, rulesNine, rulesAmericanka
    case nothingToUndo, callPocket
    case menuAbout, menuHide, menuHideOthers, menuShowAll, menuQuit
    case menuView, menuFullScreen, menuExitFullScreen, menuWindow, menuMinimize, menuZoom, menuHelp, menuGameHelp
    case aboutCredits

    /// The name of a computer level, from 1 to 5.
    static func levelName(_ level: Int) -> Str {
        [.level1, .level2, .level3, .level4, .level5][min(max(level, 1), 5) - 1]
    }

    /// The name of a pocket, from 0 to 5.
    static func pocketName(_ pocket: Int) -> Str {
        [.pocket0, .pocket1, .pocket2, .pocket3, .pocket4, .pocket5][min(max(pocket, 0), 5)]
    }

    func text(_ language: Language) -> String {
        let (english, russian) = pair
        return language == .russian ? russian : english
    }

    private var pair: (String, String) {
        switch self {
        case .title: ("3D Billiards", "Бильярд 3D")
        case .game: ("Game", "Игра")
        case .gameEight: ("Eight-ball", "Восьмёрка")
        case .gameNine: ("Nine-ball", "Девятка")
        case .gameAmericanka: ("Free pyramid", "Американка")
        case .mode: ("Mode", "Режим")
        case .modeComputer: ("Vs computer", "С компьютером")
        case .modeTwoPlayers: ("Two players", "Два игрока")
        case .modePractice: ("Practice", "Тренировка")
        case .modeDemo: ("Demo game", "Демонстрация")
        case .level: ("Level", "Уровень")
        case .level1: ("Novice", "Новичок")
        case .level2: ("Beginner", "Начинающий")
        case .level3: ("Amateur", "Любитель")
        case .level4: ("Strong", "Сильный")
        case .level5: ("Master", "Мастер")
        case .aim: ("Aim lines", "Прицел")
        case .aimFull: ("Full", "Полный")
        case .aimShort: ("Short", "Короткий")
        case .aimOff: ("Off", "Нет")
        case .theme: ("Theme", "Тема")
        case .sound: ("Sound", "Звук")
        case .languageName: ("English", "Русский")
        case .camera: ("View", "Вид")
        case .cameraOverview: ("Overview", "Обзор")
        case .cameraBehind: ("Behind the ball", "За шаром")
        case .cameraTop: ("From above", "Сверху")
        case .newGame: ("New game", "Новая партия")
        case .undoShot: ("Undo shot", "Отменить удар")
        case .nameYou: ("You", "Вы")
        case .nameComputer: ("Computer", "Компьютер")
        case .namePlayer: ("Player {}", "Игрок {}")
        case .nameComputerN: ("Computer {}", "Компьютер {}")
        case .shotYou: ("Your shot", "Ваш удар")
        case .shotComputer: ("Computer's shot", "Удар компьютера")
        case .shotPlayer: ("Player {} to shoot", "Удар игрока {}")
        case .shotComputerN: ("Computer {} to shoot", "Удар компьютера {}")
        case .practice: ("Practice", "Тренировка")
        case .winYou: ("You win!", "Вы победили!")
        case .winComputer: ("The computer wins", "Победил компьютер")
        case .winPlayer: ("Player {} wins!", "Победил игрок {}!")
        case .winComputerN: ("Computer {} wins", "Победил компьютер {}")
        case .tableCleared: ("Table cleared!", "Стол чист!")
        case .breakYou: ("You break", "Вы разбиваете")
        case .breakComputer: ("The computer breaks", "Разбивает компьютер")
        case .breakPlayer: ("Player {} breaks", "Разбивает игрок {}")
        case .breakComputerN: ("Computer {} breaks", "Разбивает компьютер {}")
        case .breaking: ("Break the rack", "Разбой пирамиды")
        case .thinking: ("Thinking…", "Думает…")
        case .aiming: ("Taking aim…", "Прицеливается…")
        case .rolling: ("The balls are rolling", "Шары катятся")
        case .pressNew: ("N or «New game» to play again", "N или «Новая партия» — сыграть ещё")
        case .ballInHand: ("Ball in hand: place the cue ball", "Шар с руки: поставьте биток")
        case .ballInKitchen: ("Ball in hand behind the line", "Шар с руки из «дома», за линией")
        case .openTable: ("Open table", "Стол открыт")
        case .solids: ("Solids", "Сплошные")
        case .stripes: ("Stripes", "Полосатые")
        case .onEight: ("The 8 to the {}", "Восьмёрка: {}")
        case .hitLowest: ("Hit the {} first", "Сначала — шар {}")
        case .anyBall: ("Any ball at any ball", "Любой шар по любому")
        case .pocket0: ("near left corner", "ближняя левая угловая")
        case .pocket1: ("near side pocket", "ближняя средняя")
        case .pocket2: ("near right corner", "ближняя правая угловая")
        case .pocket3: ("far left corner", "дальняя левая угловая")
        case .pocket4: ("far side pocket", "дальняя средняя")
        case .pocket5: ("far right corner", "дальняя правая угловая")
        case .cueBall: ("cue ball", "биток")
        case .foul: ("Foul: {}", "Фол: {}")
        case .foulScratch: ("the cue ball went in", "биток в лузе")
        case .foulMiss: ("no ball was hit", "промах по шарам")
        case .foulWrongBall: ("the wrong ball was hit first", "первым задет не тот шар")
        case .foulNoRail: ("no ball reached a cushion", "ни один шар не коснулся борта")
        case .foulEightEarly: ("the 8 went in too early", "восьмёрка забита раньше времени")
        case .foulEightWrongPocket: ("the 8 went into the wrong pocket", "восьмёрка не в ту лузу")
        case .foulEightOnFoul: ("the 8 went in on a foul", "восьмёрка забита с фолом")
        case .logPotted: ("{}: potted {}", "{}: забит {}")
        case .logPottedMany: ("{}: potted {}", "{}: забиты {}")
        case .logNothing: ("{}: nothing potted", "{}: без забитых")
        case .logFoul: ("{}: foul, {}", "{}: фол, {}")
        case .logSolids: ("{}: solids", "{}: сплошные")
        case .logStripes: ("{}: stripes", "{}: полосатые")
        case .logBack: ("Back on the table: {}", "Возвращены на стол: {}")
        case .logWin: ("{} won the game", "{}: победа")
        case .power: ("Power", "Сила")
        case .spin: ("Spin", "Винт")
        case .metresPerSecond: ("m/s", "м/с")
        case .history: ("Shots", "Ход партии")
        case .noShotsYet: ("No shots yet", "Ударов ещё не было")
        case .shots: ("{} shots", "Ударов: {}")
        case .left: ("{} left", "Осталось: {}")
        case .toWin: ("of {}", "из {}")
        case .footer: ("F1 help · Tab panel · ⌃⌘F full screen", "F1 справка · Tab панель · ⌃⌘F весь экран")
        case .controls: ("Controls", "Управление")
        case .keyMove: ("Mouse", "Мышь")
        case .keyShiftMove: ("Shift + mouse", "Shift + мышь")
        case .keyPull: ("Press, pull back", "Нажать и оттянуть")
        case .keyClick: ("Click ball / pocket", "Щелчок: шар / луза")
        case .keyDragCue: ("Drag the cue ball", "Тащить биток")
        case .keyRightDrag: ("Right drag", "Правая кнопка")
        case .keyWheel: ("Scroll or pinch", "Прокрутка или щипок")
        case .helpAim: ("Aim at the point", "Прицел в точку")
        case .helpFineAim: ("Fine aim", "Точная наводка")
        case .helpStrike: ("Strike: farther is harder", "Удар: дальше — сильнее")
        case .helpClick: ("Pick the ball or call the pocket", "Выбрать шар или лузу")
        case .helpPlace: ("Place a ball in hand", "Поставить шар с руки")
        case .helpRotate: ("Turn the view", "Повернуть вид")
        case .helpZoom: ("Zoom in and out", "Приблизить и отдалить")
        case .helpShoot: ("Strike with the power set", "Удар с заданной силой")
        case .helpPower: ("Power", "Сила удара")
        case .helpTurn: ("Turn the aim (Shift: finer)", "Поворот прицела (Shift — точнее)")
        case .helpSpin: ("Spin: where the cue strikes", "Винт: куда бьёт кий")
        case .helpCenter: ("Strike the middle", "Удар в центр")
        case .helpCamera: ("Next view", "Следующий вид")
        case .helpGuide: ("Aim lines", "Прицельные линии")
        case .helpUndo: ("Undo the shot", "Отменить удар")
        case .helpNew: ("New game", "Новая партия")
        case .helpGame: ("Next game", "Следующая игра")
        case .helpMode: ("Who plays", "Кто играет")
        case .helpLevel: ("Computer level", "Уровень компьютера")
        case .helpTheme: ("Next theme", "Следующая тема")
        case .helpSound: ("Sound on or off", "Звук вкл/выкл")
        case .helpLanguage: ("English / Russian", "Русский / английский")
        case .helpPanel: ("Show or hide the panel", "Показать/скрыть панель")
        case .helpFullScreen: ("Full screen", "Весь экран")
        case .helpClose: ("Close this help", "Закрыть справку")
        case .rules: ("Rules", "Правила")
        case .rulesEight:
            ("Eight-ball. The first ball potted after the break gives the shooter a group: solids (1–7) or stripes (9–15). Hit a ball of your "
                + "group first, then pot a ball or send one to a cushion. Potting your balls keeps the turn. With the group cleared, pot the 8 in "
                + "the pocket called. The 8 potted early or on a foul loses. After a foul the opponent has ball in hand.",
             "Восьмёрка. Первый шар, забитый после разбоя, даёт группу: сплошные (1–7) или полосатые (9–15). Первым касайтесь шара своей "
                + "группы, затем забейте шар или доведите любой до борта. Забили свой — бьёте снова. Очистив группу, забейте восьмёрку в "
                + "заказанную лузу. Восьмёрка, забитая раньше или с фолом, — поражение. После фола соперник получает шар с руки.")
        case .rulesNine:
            ("Nine-ball. The cue ball must first hit the lowest ball on the table. Any ball potted on a fair shot keeps the turn, and the 9 "
                + "potted on a fair shot wins, even early. A shot that pots nothing must send a ball to a cushion. After a foul the opponent "
                + "has ball in hand anywhere.",
             "Девятка. Биток должен первым коснуться шара с наименьшим номером. Любой шар, забитый без фола, даёт следующий удар, а девятка, "
                + "забитая без фола, — победу, даже раньше времени. Если ничего не забито, какой-то шар должен коснуться борта. После фола "
                + "соперник ставит биток куда угодно.")
        case .rulesAmericanka:
            ("Free pyramid. Sixteen balls on a big table with tight pockets. After the break any ball may be struck at any other; every ball "
                + "potted on a fair shot counts, the struck one too, and the shooter goes on. Hitting nothing, or potting nothing with no ball "
                + "reaching a cushion, is a foul: one of the shooter's balls goes back on the table. Eight balls win.",
             "Американка. Шестнадцать шаров на большом столе с узкими лузами. После разбоя можно бить любым шаром по любому; каждый шар, "
                + "забитый без фола, засчитывается, в том числе биток, и удар повторяется. Промах или удар без забитого шара, после которого "
                + "ни один шар не коснулся борта, — фол: один из шаров нарушителя возвращается на стол. Побеждает забивший восемь.")
        case .nothingToUndo: ("No shots to take back", "Нечего отменять")
        case .callPocket: ("Click a pocket to call it for the 8", "Щёлкните по лузе, чтобы заказать её")
        case .menuAbout: ("About 3D Billiards", "Об игре «Бильярд 3D»")
        case .menuHide: ("Hide 3D Billiards", "Скрыть «Бильярд 3D»")
        case .menuHideOthers: ("Hide Others", "Скрыть остальные")
        case .menuShowAll: ("Show All", "Показать все")
        case .menuQuit: ("Quit 3D Billiards", "Завершить «Бильярд 3D»")
        case .menuView: ("View", "Вид")
        case .menuFullScreen: ("Enter Full Screen", "Войти в полноэкранный режим")
        case .menuExitFullScreen: ("Exit Full Screen", "Выйти из полноэкранного режима")
        case .menuWindow: ("Window", "Окно")
        case .menuMinimize: ("Minimize", "Свернуть")
        case .menuZoom: ("Zoom", "Изменить масштаб")
        case .menuHelp: ("Help", "Справка")
        case .menuGameHelp: ("3D Billiards Help", "Справка «Бильярд 3D»")
        case .aboutCredits:
            ("Eight-ball, nine-ball and the Russian free pyramid, with a computer opponent of five levels. Written in Swift on Metal, "
                + "with no engine, library or asset file.",
             "Восьмёрка, девятка и русская «Американка», компьютерный соперник пяти уровней. Написано на Swift и Metal, без движка, "
                + "библиотек и файлов ресурсов.")
        }
    }
}
