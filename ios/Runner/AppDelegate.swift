import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let workoutNotificationChannel = "jimbro/workout_notifications"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let didLaunch = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    configureWorkoutNotificationChannel()
    return didLaunch
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  private func configureWorkoutNotificationChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return
    }

    let channel = FlutterMethodChannel(
      name: workoutNotificationChannel,
      binaryMessenger: controller.binaryMessenger
    )

    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "requestPermission":
        UNUserNotificationCenter.current().requestAuthorization(
          options: [.alert, .sound, .badge]
        ) { granted, _ in
          DispatchQueue.main.async {
            result(granted)
          }
        }
      case "scheduleWeeklyWorkout":
        guard let args = call.arguments as? [String: Any] else {
          result(false)
          return
        }
        self.scheduleWeeklyWorkout(args: args)
        result(true)
      case "cancelWorkoutNotification":
        guard let args = call.arguments as? [String: Any],
              let id = args["id"] as? String else {
          result(false)
          return
        }
        UNUserNotificationCenter.current()
          .removePendingNotificationRequests(withIdentifiers: [id])
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func scheduleWeeklyWorkout(args: [String: Any]) {
    let id = args["id"] as? String ?? "workout-schedule"
    let title = args["title"] as? String ?? "JimBro workout"
    let body = args["body"] as? String ?? "Time for your scheduled workout."
    let weekday = args["weekday"] as? Int ?? 1
    let hour = args["hour"] as? Int ?? 18
    let minute = args["minute"] as? Int ?? 0

    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default

    var date = DateComponents()
    date.weekday = weekday == 7 ? 1 : weekday + 1
    date.hour = min(max(hour, 0), 23)
    date.minute = min(max(minute, 0), 59)

    let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
    let request = UNNotificationRequest(
      identifier: id,
      content: content,
      trigger: trigger
    )

    UNUserNotificationCenter.current()
      .removePendingNotificationRequests(withIdentifiers: [id])
    UNUserNotificationCenter.current().add(request)
  }
}
