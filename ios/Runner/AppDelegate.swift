import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, FlutterStreamHandler {
  private var exportProgressSink: FlutterEventSink?
  private var activeExportSession: AVAssetExportSession?
  private var activeExportId: String?
  private var activeExportWasCancelled = false
  private var exportProgressTimer: Timer?

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
    let exportProgressChannel = FlutterEventChannel(
      name: "pitchcut_ai/video_export_progress",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    exportProgressChannel.setStreamHandler(self)
    trimChannel.setMethodCallHandler { [weak self] call, result in
      if call.method == "generateThumbnail" {
        self?.generateThumbnail(arguments: call.arguments, result: result)
        return
      }
      if call.method == "exportTimeline" {
        self?.exportTimeline(arguments: call.arguments, result: result)
        return
      }
      if call.method == "startExportTimeline" {
        self?.exportTimeline(arguments: call.arguments, result: result, tracked: true)
        return
      }
      if call.method == "cancelExport" {
        self?.cancelExport(arguments: call.arguments, result: result)
        return
      }
      guard call.method == "trimVideo" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.trimVideo(arguments: call.arguments, result: result)
    }
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    exportProgressSink = events
    events(["type": "ready"])
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    exportProgressSink = nil
    return nil
  }

  private func emitExportProgress(exportId: String, progress: Float) {
    exportProgressSink?([
      "exportId": exportId,
      "type": "progress",
      "progress": max(0, min(1, progress))
    ])
  }

  private func cancelExport(arguments: Any?, result: @escaping FlutterResult) {
    guard
      let values = arguments as? [String: Any],
      let exportId = values["exportId"] as? String,
      exportId == activeExportId,
      let session = activeExportSession
    else {
      result(nil)
      return
    }
    activeExportWasCancelled = true
    session.cancelExport()
    result(nil)
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

  private func exportTimeline(
    arguments: Any?,
    result: @escaping FlutterResult,
    tracked: Bool = false
  ) {
    guard
      let values = arguments as? [String: Any],
      let clips = values["clips"] as? [[String: Any]],
      let outputPath = values["outputPath"] as? String,
      !clips.isEmpty
    else {
      result(FlutterError(code: "invalid_timeline", message: "There are no clips to export.", details: nil))
      return
    }
    if tracked && (activeExportSession != nil || activeExportId != nil) {
      result(FlutterError(code: "export_busy", message: "Another video export is already running.", details: nil))
      return
    }
    let exportId = tracked ? values["exportId"] as? String : nil
    let qualityHeight = tracked ? values["qualityHeight"] as? Int : nil
    if tracked && (exportId == nil || ![480, 720, 1080].contains(qualityHeight ?? 0)) {
      result(FlutterError(code: "invalid_export_settings", message: "The export quality is invalid.", details: nil))
      return
    }
    if tracked {
      activeExportId = exportId
      activeExportWasCancelled = false
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
      if tracked { clearActiveExport() }
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
      if tracked { clearActiveExport() }
      result(FlutterError(code: "export_failed", message: error.localizedDescription, details: nil))
      return
    }

    Task { @MainActor in
      do {
        var timelineCursor = CMTime.zero
        var videoInstructions: [AVMutableVideoCompositionInstruction] = []
        var outputSize = CGSize.zero
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
          let rotationDegrees = clip["rotationDegrees"] as? Int ?? 0
          guard [0, 90, 180, 270].contains(rotationDegrees) else {
            throw NSError(domain: "VideoTimeline", code: 4, userInfo: [
              NSLocalizedDescriptionKey: "A timeline rotation value is invalid."
            ])
          }
          let crop = clip["crop"] as? [String: Any]
          let left = CGFloat((crop?["left"] as? NSNumber)?.doubleValue ?? 0)
          let top = CGFloat((crop?["top"] as? NSNumber)?.doubleValue ?? 0)
          let right = CGFloat((crop?["right"] as? NSNumber)?.doubleValue ?? 1)
          let bottom = CGFloat((crop?["bottom"] as? NSNumber)?.doubleValue ?? 1)
          guard left >= 0, top >= 0, right <= 1, bottom <= 1,
                right - left >= 0.05, bottom - top >= 0.05 else {
            throw NSError(domain: "VideoTimeline", code: 5, userInfo: [
              NSLocalizedDescriptionKey: "A timeline crop rectangle is invalid."
            ])
          }
          let naturalSize = try await sourceVideoTrack.load(.naturalSize)
          let preferredTransform = try await sourceVideoTrack.load(.preferredTransform)
          let sourceBounds = CGRect(origin: .zero, size: naturalSize)
          let orientedBounds = sourceBounds.applying(preferredTransform).standardized
          let rotation = CGAffineTransform(rotationAngle: CGFloat(rotationDegrees) * .pi / 180)
          var finalTransform = preferredTransform.concatenating(rotation)
          let transformedBounds = sourceBounds.applying(finalTransform).standardized
          finalTransform = finalTransform.concatenating(
            CGAffineTransform(translationX: -transformedBounds.minX, y: -transformedBounds.minY)
          )
          let rotatedSize = rotationDegrees % 180 == 0
            ? CGSize(width: orientedBounds.width, height: orientedBounds.height)
            : CGSize(width: orientedBounds.height, height: orientedBounds.width)
          if outputSize == .zero {
            outputSize = CGSize(width: max(2, rotatedSize.width * (right - left)),
                                height: max(2, rotatedSize.height * (bottom - top)))
          }
          let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoCompositionTrack)
          layerInstruction.setTransform(finalTransform, at: timelineCursor)
          layerInstruction.setCropRectangle(
            CGRect(x: left * rotatedSize.width, y: top * rotatedSize.height,
                   width: (right - left) * rotatedSize.width,
                   height: (bottom - top) * rotatedSize.height),
            at: timelineCursor
          )
          let videoInstruction = AVMutableVideoCompositionInstruction()
          videoInstruction.timeRange = CMTimeRange(start: timelineCursor, duration: sourceRange.duration)
          videoInstruction.layerInstructions = [layerInstruction]
          videoInstructions.append(videoInstruction)
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

        let sizePresets: [(Int, String)] = [
          (480, AVAssetExportPreset640x480),
          (720, AVAssetExportPreset1280x720),
          (1080, AVAssetExportPreset1920x1080)
        ]
        let compatiblePresets = AVAssetExportSession.exportPresets(compatibleWith: composition)
        let requestedPresets = sizePresets.filter { $0.0 <= (qualityHeight ?? 1080) }
        let selectedPreset = tracked
          ? (requestedPresets.reversed().first(where: {
              compatiblePresets.contains($0.1)
            })?.1 ?? (compatiblePresets.contains(AVAssetExportPresetHighestQuality)
              ? AVAssetExportPresetHighestQuality
              : compatiblePresets.first ?? AVAssetExportPresetHighestQuality))
          : AVAssetExportPresetHighestQuality
        guard let exportSession = AVAssetExportSession(
          asset: composition,
          presetName: selectedPreset
        ), exportSession.supportedFileTypes.contains(.mp4) else {
          throw NSError(domain: "VideoTimeline", code: 3, userInfo: [
            NSLocalizedDescriptionKey: "This timeline cannot be exported as MP4."
          ])
        }
        if tracked && self.activeExportWasCancelled {
          throw NSError(domain: "VideoExport", code: -999, userInfo: [
            NSLocalizedDescriptionKey: "Video export was cancelled."
          ])
        }
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = outputSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions = videoInstructions
        exportSession.videoComposition = videoComposition
        exportSession.shouldOptimizeForNetworkUse = true
        activeExportSession = exportSession
        if let exportId {
          exportProgressTimer?.invalidate()
          exportProgressTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self, weak exportSession] timer in
            guard let self, let exportSession, self.activeExportId == exportId else {
              timer.invalidate()
              return
            }
            self.emitExportProgress(exportId: exportId, progress: exportSession.progress)
          }
        }
        exportSession.exportAsynchronously {
          DispatchQueue.main.async {
            self.exportProgressTimer?.invalidate()
            self.exportProgressTimer = nil
            switch exportSession.status {
            case .completed:
              if let exportId { self.emitExportProgress(exportId: exportId, progress: 1) }
              self.clearActiveExport()
              result(outputPath)
            case .failed, .cancelled:
              try? FileManager.default.removeItem(at: outputURL)
              let cancelled = self.activeExportWasCancelled
              self.clearActiveExport()
              result(FlutterError(
                code: cancelled ? "export_cancelled" : "export_failed",
                message: cancelled ? "Video export was cancelled." :
                  (exportSession.error?.localizedDescription ?? "Video export failed."),
                details: nil
              ))
            default:
              self.clearActiveExport()
              result(FlutterError(code: "export_failed", message: "Video export did not complete.", details: nil))
            }
          }
        }
      } catch {
        DispatchQueue.main.async {
          let cancelled = self.activeExportWasCancelled
          self.clearActiveExport()
          try? FileManager.default.removeItem(at: outputURL)
          result(FlutterError(
            code: cancelled ? "export_cancelled" : "export_failed",
            message: cancelled ? "Video export was cancelled." : error.localizedDescription,
            details: nil
          ))
        }
      }
    }
  }

  private func clearActiveExport() {
    activeExportSession = nil
    activeExportId = nil
    activeExportWasCancelled = false
  }
}
