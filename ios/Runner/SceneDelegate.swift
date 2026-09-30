import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    warmUpKeyboard(in: scene)
  }

  private func warmUpKeyboard(in scene: UIScene) {
    DispatchQueue.main.async {
      guard
        let windowScene = scene as? UIWindowScene,
        let window = windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first
      else {
        return
      }

      let warmupField = UITextField(frame: .zero)
      warmupField.autocorrectionType = .no
      window.addSubview(warmupField)
      warmupField.becomeFirstResponder()
      warmupField.resignFirstResponder()
      warmupField.removeFromSuperview()
    }
  }
}
