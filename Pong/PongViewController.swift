/// Импортируем библиотеку UI-компонентов (элементы интерфейса)
import UIKit
import AVFoundation

/// Это класс единственного экрана нашего приложения
///
/// В классе есть элементы отображения игры:
/// - `ballView` - мяч
/// - `userPaddleView` - платформа игрока
/// - `enemyPaddleView` - платформа сопернка
///
/// Также в классе данного экрана настраивается физика взаимодействия элементов
/// в функции `enableDynamics()`
///
/// А еще в этом классе реализована обработка движения пальца по экрану,
/// с помощью обработки этого жеста игрок может двигать свою платформу и отталкивать мяч
///
class PongViewController: UIViewController {

    // MARK: - Overriden Properties

    /// Эта переопределенная переменная определяет допустимые ориентации экрана
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }

    // MARK: - Subviews

    /// Это переменная отображения мяча
    @IBOutlet var ballView: UIView!

    /// Это переменная отображения платформы игрока
    @IBOutlet var userPaddleView: UIView!

    /// Это переменная отображения платформы соперника
    @IBOutlet var enemyPaddleView: UIView!

    /// Это переменная отображения разделяющей линии
    @IBOutlet var lineView: UIView!

    /// Это переменная отображения лэйбла со счетом игрока
    @IBOutlet var userScoreLabel: UILabel!
    
    @IBOutlet var enemyScoreLabel: UILabel!
    
    @IBOutlet var winnerLabel: UILabel!

    // MARK: - Instance Properties

    /// Это переменная обработчика жеста движения пальцем по экрану
    var panGestureRecognizer: UIPanGestureRecognizer?

    /// Это переменная в которой мы будем запоминать последнее положение платформы пользователя,
    /// перед тем как пользователь начал двигать пальцем по экрану
    var lastUserPaddleOriginLocation: CGFloat = 0

    /// Это переменная таймера, который будет обновлять положение платформы соперника
    var enemyPaddleUpdateTimer: Timer?

    /// Это флаг `Bool`, имеет два возможных значения:
    /// - `true` - можно трактовать как "да"
    /// - `false` - можно трактовать как "нет"
    ///
    /// Он отвечает за необходимость запустить мяч по следующему нажатию на экран
    ///
    var shouldLaunchBallOnNextTap: Bool = false

    /// Это флаг `Bool`, который указывает "был ли запущен мяч"
    var hasLaunchedBall: Bool = false

    var enemyPaddleUpdatesCounter: UInt8 = 0

    // NOTE: Все переменные ниже вплоть до 74-ой строки необходимы для настроек физики
    // Мы не будем вдаваться в подробности того, что это такое и как устроено
    var dynamicAnimator: UIDynamicAnimator?
    var ballPushBehavior: UIPushBehavior?
    var ballDynamicBehavior: UIDynamicItemBehavior?
    var userPaddleDynamicBehavior: UIDynamicItemBehavior?
    var enemyPaddleDynamicBehavior: UIDynamicItemBehavior?
    var collisionBehavior: UICollisionBehavior?

    // NOTE: Все переменный вплоть до 82-ой строки используются для реагирования
    // на стлокновения мяча - проигрывание звука столкновения и вибро-отклик
    var audioPlayers: [AVAudioPlayer] = []
    var audioPlayersLock = NSRecursiveLock()
    var softImpactFeedbackGenerator = UIImpactFeedbackGenerator(style: .soft)
    var lightImpactFeedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    var rigidImpactFeedbackGenerator = UIImpactFeedbackGenerator(style: .rigid)

    /// Эта переменная плеера предназначена для повторяющегося проигрывания фоновой музыки в игре
    var backgroundSoundAudioPlayer: AVAudioPlayer? = {
        guard
            let backgroundSoundURL = Bundle.main.url(forResource: "background", withExtension: "wav"),
            let audioPlayer = try? AVAudioPlayer(contentsOf: backgroundSoundURL)
        else { return nil }

        audioPlayer.volume = 0.5
        audioPlayer.numberOfLoops = -1

        return audioPlayer
    }()

    var userScore: Int = 0 {
        didSet {
            updateScoreLabel(player: "user")
            checkIfGameHasEnded()
        }
    }
    
    var enemyScore: Int = 0 {
        didSet {
            updateScoreLabel(player: "enemy")
            checkIfGameHasEnded()
        }
    }
    
    let maxScore: Int = 5;
    var gameHasEnded: Bool = false;

    override func viewDidLoad() {
        super.viewDidLoad()

        configurePongGame()
        
        self.ballView.backgroundColor = UIColor.green
    }

    /// Эта функция вызывается, когда экран PongViewController повяился на экране телефона
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // NOTE: Включаем динамику взаимодействия
        self.enableDynamics()
    }

    /// Эта функция вызывается, когда экран первый раз отрисовал весь свой интерфейс
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // NOTE: Устанавливаем шару радиус скругления равный половине высоты
        ballView.layer.cornerRadius = ballView.bounds.size.height / 2
    }

    override func touchesBegan(
        _ touches: Set<UITouch>,
        with event: UIEvent?
    ) {
        super.touchesBegan(touches, with: event)

        // NOTE: Если нужно запустить мяч и мяч еще не был запущен - запускаем мяч
        if shouldLaunchBallOnNextTap, !hasLaunchedBall {
            hasLaunchedBall = true

            launchBall()
        }
    }

    // MARK: - Private Methods

    /// Эта функция выполняет выполняет всю конфигурацию (настройку) экрана
    ///
    /// - включает обработку жеста движения пальцем по экрану
    /// - включает динамику взаимодействия элементов
    /// - указывает что при следующем нажатии мяч должен запуститься
    ///
    private func configurePongGame() {
        // NOTE: Настраиваем лэйбл со счетом игрока
        updateScoreLabel(player: "user")
        updateScoreLabel(player: "enemy")

        // NOTE: Включаем обработку жеста движения пальцем по экрану
        self.enabledPanGestureHandling()

        // NOTE: Включаем логику платформы противника "следовать за мечом"
        self.enableEnemyPaddleFollowBehavior()

        // NOTE: Указываем, что при следующем нажатии на экран нужно запустить мяч
        self.shouldLaunchBallOnNextTap = true

        // NOTE: Начинаем проигрывать фоновую музыку
        self.backgroundSoundAudioPlayer?.prepareToPlay()
        self.backgroundSoundAudioPlayer?.play()
    }
    
    private func updateScoreLabel(player: String) {
        if player == "user" {
            userScoreLabel.text = "\(userScore)"
        } else {
            enemyScoreLabel.text = "\(enemyScore)"
        }
    }
    
    private func checkIfGameHasEnded() {
        if gameHasEnded {
            return
        }
        
        if (userScore >= maxScore) || (enemyScore >= maxScore) {
            gameHasEnded = true
            
            winnerLabel.text = "Winner is " + (userScore >= maxScore ? "user" : "AI")
            winnerLabel.isHidden = false
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.winnerLabel.isHidden = true
                self.userScore = 0
                self.enemyScore = 0
                self.gameHasEnded = false
            }
        }
    }
}
