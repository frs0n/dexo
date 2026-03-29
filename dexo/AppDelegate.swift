//
//  AppDelegate.swift
//  dexo
//
//  Created by Eilgnaw on 3/21/26.
//

import SDWebImage
import SDWebImageSVGCoder
import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        SDImageCodersManager.shared.addCoder(SDImageSVGCoder.shared)
        ProxyManager.shared.start()
        configureSDWebImageProxy()
        return true
    }

    // MARK: UISceneSession Lifecycle

    private func configureSDWebImageProxy() {
        guard let proxy = ProxyManager.shared.proxyConfiguration else { return }
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.connectionProxyDictionary = proxy
        let downloaderConfig = SDWebImageDownloaderConfig()
        downloaderConfig.sessionConfiguration = sessionConfig
        let downloader = SDWebImageDownloader(config: downloaderConfig)
        SDWebImageManager.shared.optionsProcessor = SDWebImageOptionsProcessor { url, options, context in
            var mutableContext = context ?? [:]
            mutableContext[.imageLoader] = downloader
            return SDWebImageOptionsResult(options: options.union(.allowInvalidSSLCertificates), context: mutableContext)
        }
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }
}
