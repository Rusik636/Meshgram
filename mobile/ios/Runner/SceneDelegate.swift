import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    if let windowScene = scene as? UIWindowScene,
       let app = UIApplication.shared.delegate as? AppDelegate {
      let window = UIWindow(windowScene: windowScene)
      window.rootViewController = FlutterViewController(engine: app.engine, nibName: nil, bundle: nil)
      self.window = window
      window.makeKeyAndVisible()
    }
    super.scene(scene, willConnectTo: session, options: connectionOptions)
  }
}
