import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let trimChannel = FlutterMethodChannel(
      name: "pitchcut_ai/video_trim",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    trimChannel.setMethodCallHandler { [weak self] call, result in
      if call.method == "generateThumbnail" {
        self?.generateThumbnail(arguments: call.arguments, result: result)
        return
      }
      if call.method == "exportTimeline" {
        self?.exportTimeline(arguments: call.arguments, result: result)
        return
      }
      guard call.method == "trimVideo" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.trimVideo(arguments: call.arguments, result: result)
    }
  }

  private func generateThumbnail(arguments: Any?, result: @escaping FlutterResult) {
    guard
      let values = arguments as? [String: Any],
      let inputPath = values["inputPath"] as? String,
      FileManager.default.fileExists(atPath: inputPath)
    else {
      result(FlutterError(code: "missing_input", message: "The selected video file was not found.", details: nil))
      return
    }
    let timeMs = values["timeMs"] as? Int ?? 0
    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: URL(fileURLWithPath: inputPath)))
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: 280, height: 280)
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        let frame = try generator.copyCGImage(
          at: CMTime(value: Int64(max(0, timeMs)), timescale: 1000),
          actualTime: nil
        )
        guard let data = UIImage(cgImage: frame).jpegData(compressionQuality: 0.7) else {
          DispatchQueue.main.async { result(nil) }
          return
        }
        DispatchQueue.main.async {
          result(FlutterStandardTypedData(bytes: data))
        }
      } catch {
        DispatchQueue.main.async { result(nil) }
      }
    }
  }

  private func trimVideo(arguments: Any?, result: @escaping FlutterResult) {
    guard
      let values = arguments as? [String: Any],
      let inputPath = values["inputPath"] as? String,
      let outputPath = values["outputPath"] as? String,
      let startMs = values["startMs"] as? Int,
      let endMs = values["endMs"] as? Int,
      startMs >= 0,
      endMs > startMs
    else {
      result(FlutterError(code: "invalid_trim_range", message: "The trim range is invalid.", details: nil))
      return
    }

    let inputURL = URL(fileURLWithPath: inputPath)
    let outputURL = URL(fileURLWithPath: outputPath)
    guard FileManager.default.fileExists(atPath: inputPath) else {
      result(FlutterError(code: "missing_input", message: "The selected video file was not found.", details: nil))
      return
    }

    do {
      try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      if FileManager.default.fileExists(atPath: outputPath) {
        try FileManager.default.removeItem(at: outputURL)
      }
    } catch {
      result(FlutterError(code: "trim_failed", message: error.localizedDescription, details: nil))
      return
    }

    let asset = AVURLAsset(url: inputURL)
    guard let exportSession = AVAssetExportSession(
      asset: asset,
      presetName: AVAssetExportPresetHighestQuality
    ) else {
      result(FlutterError(code: "trim_failed", message: "Could not create a video export session.", details: nil))
      return
    }
    guard exportSession.supportedFileTypes.contains(.mp4) else {
      result(FlutterError(code: "unsupported_format", message: "This video cannot be exported as MP4.", details: nil))
      return
    }

    exportSession.outputURL = outputURL
    exportSession.outputFileType = .mp4
    exportSession.timeRange = CMTimeRange(
      start: CMTime(value: Int64(startMs), timescale: 1000),
      duration: CMTime(value: Int64(endMs - startMs), timescale: 1000)
    )
    exportSession.exportAsynchronously {
      DispatchQueue.main.async {
        switch exportSession.status {
        case .completed:
          result(outputPath)
        case .failed, .cancelled:
          try? FileManager.default.removeItem(at: outputURL)
          result(FlutterError(
            code: "trim_failed",
            message: exportSession.error?.localizedDescription ?? "Video trimming failed.",
            details: nil
          ))
        default:
          result(FlutterError(code: "trim_failed", message: "Video trimming did not complete.", details: nil))
        }
      }
    }
  }

  private func exportTimeline(arguments: Any?, result: @escaping FlutterResult) {
    guard
      let values = arguments as? [String: Any],
      let clips = values["clips"] as? [[String: Any]],
      let outputPath = values["outputPath"] as? String,
      !clips.isEmpty
    else {
      result(FlutterError(code: "invalid_timeline", message: "There are no clips to export.", details: nil))
      return
    }

    let composition = AVMutableComposition()
    guard
      let videoCompositionTrack = composition.addMutableTrack(
        withMediaType: .video,
        preferredTrackID: kCMPersistentTrackID_Invalid
      ),
      let audioCompositionTrack = composition.addMutableTrack(
        withMediaType: .audio,
        preferredTrackID: kCMPersistentTrackID_Invalid
      )
    else {
      result(FlutterError(code: "export_failed", message: "Could not create the video composition.", details: nil))
      return
    }

    let outputURL = URL(fileURLWithPath: outputPath)
    do {
      try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      if FileManager.default.fileExists(atPath: outputPath) {
        try FileManager.default.removeItem(at: outputURL)
      }
    } catch {
      result(FlutterError(code: "export_failed", message: error.localizedDescription, details: nil))
      return
    }

    Task {
      do {
        var timelineCursor = CMTime.zero
        for clip in clips {
          guard
            let inputPath = clip["inputPath"] as? String,
            let startMs = clip["startMs"] as? Int,
            let endMs = clip["endMs"] as? Int,
            startMs >= 0,
            endMs > startMs,
            FileManager.default.fileExists(atPath: inputPath)
          else {
            throw NSError(domain: "VideoTimeline", code: 1, userInfo: [
              NSLocalizedDescriptionKey: "A timeline clip is invalid or missing."
            ])
          }

          let asset = AVURLAsset(url: URL(fileURLWithPath: inputPath))
          let videoTracks = try await asset.loadTracks(withMediaType: .video)
          guard let sourceVideoTrack = videoTracks.first else {
            throw NSError(domain: "VideoTimeline", code: 2, userInfo: [
              NSLocalizedDescriptionKey: "A timeline item has no video track."
            ])
          }
          let sourceRange = CMTimeRange(
            start: CMTime(value: Int64(startMs), timescale: 1000),
            duration: CMTime(value: Int64(endMs - startMs), timescale: 1000)
          )
          try videoCompositionTrack.insertTimeRange(
            sourceRange,
            of: sourceVideoTrack,
            at: timelineCursor
          )

          let audioTracks = try await asset.loadTracks(withMediaType: .audio)
          if let sourceAudioTrack = audioTracks.first {
            try audioCompositionTrack.insertTimeRange(
              sourceRange,
              of: sourceAudioTrack,
              at: timelineCursor
            )
          } else {
            audioCompositionTrack.insertEmptyTimeRange(
              CMTimeRange(start: timelineCursor, duration: sourceRange.duration)
            )
          }
          timelineCursor = CMTimeAdd(timelineCursor, sourceRange.duration)
        }

        guard let exportSession = AVAssetExportSession(
          asset: composition,
          presetName: AVAssetExportPresetHighestQuality
        ), exportSession.supportedFileTypes.contains(.mp4) else {
          throw NSError(domain: "VideoTimeline", code: 3, userInfo: [
            NSLocalizedDescriptionKey: "This timeline cannot be exported as MP4."
          ])
        }
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.exportAsynchronously {
          DispatchQueue.main.async {
            switch exportSession.status {
            case .completed:
              result(outputPath)
            case .failed, .cancelled:
              try? FileManager.default.removeItem(at: outputURL)
              result(FlutterError(
                code: "export_failed",
                message: exportSession.error?.localizedDescription ?? "Video export failed.",
                details: nil
              ))
            default:
              result(FlutterError(code: "export_failed", message: "Video export did not complete.", details: nil))
            }
          }
        }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "export_failed", message: error.localizedDescription, details: nil))
        }
      }
    }
  }
}
