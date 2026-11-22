// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import Foundation

enum RadioPushProtocol: String {
  case meshcore, meshtastic

  var prefix: [UInt8] { self == .meshcore ? [0x3e] : [0x94, 0xc3] }
  var maxPayload: Int { self == .meshcore ? 176 : 512 }
  var boot: Data {
    switch self {
    case .meshcore:
      return encode([1, 3, 0, 0, 0, 0, 0, 0] + Array("Meshgram".utf8))
    case .meshtastic:
      return Data([0x94, 0x94, 0x94, 0x94]) + encode([0x18, 0x01])
    }
  }

  func encode(_ payload: [UInt8]) -> Data {
    let low = UInt8(truncatingIfNeeded: payload.count)
    let high = UInt8(payload.count >> 8)
    switch self {
    case .meshcore: return Data([0x3c, low, high] + payload)
    case .meshtastic: return Data(prefix + [high, low] + payload)
    }
  }

  func frames(_ buffer: inout [UInt8]) -> [[UInt8]] {
    var frames: [[UInt8]] = []
    let prefix = self.prefix
    let header = prefix.count + 2
    var offset = 0
    while buffer.count - offset >= header {
      guard buffer[offset..<(offset + prefix.count)].elementsEqual(prefix) else {
        offset += 1
        continue
      }
      let a = Int(buffer[offset + prefix.count])
      let b = Int(buffer[offset + prefix.count + 1])
      let size = self == .meshcore ? a | b << 8 : a << 8 | b
      guard size > 0, size <= maxPayload else {
        offset += 1
        continue
      }
      let end = offset + header + size
      guard end <= buffer.count else { break }
      frames.append(Array(buffer[(offset + header)..<end]))
      offset = end
    }
    buffer.removeFirst(offset)
    return frames
  }

  struct Message {
    let id: String
    let chat: String
    let author: String
    let text: String
    let reaction: Bool
    let reactionTarget: String?
  }

  func message(_ frame: [UInt8], radio: LocalPushRadio) -> Message? {
    if self == .meshcore {
      guard let type = frame.first, [7, 8, 16, 17].contains(type) else { return nil }
      let direct = type == 7 || type == 16
      let base = type >= 16 ? 4 : 1
      let stamp = base + (direct ? 8 : 3)
      guard frame.count > stamp + 4, [0, 2].contains(frame[stamp - 1]) else { return nil }
      let start = stamp + 4 + (direct && frame[stamp - 1] == 2 ? 4 : 0)
      guard frame.count > start else { return nil }
      let wire = String(decoding: frame[start...].prefix { $0 != 0 }, as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      let chat = direct ? "node:" + Self.hex(frame[base..<(base + 6)]) : "ch:\(frame[base])"
      let timestamp = (0..<4).reduce(UInt32(0)) { $0 | UInt32(frame[stamp + $1]) << ($1 * 8) }
      let id = "mc:\(chat):\(timestamp):" + Data(wire.utf8).base64EncodedString()
      let separator = direct ? nil : wire.range(of: ": ").flatMap { range in
        range.lowerBound == wire.startIndex ? nil : range
      }
      let author = direct ? radio.peers[chat] ?? String(chat.dropFirst(5))
        : separator.map { String(wire[..<$0.lowerBound]) } ?? ""
      let text = separator.map { String(wire[$0.upperBound...]) } ?? wire
      guard !text.isEmpty else { return nil }
      let reactionTarget = Self.meshCoreReaction(text, direct: direct)
      return Message(id: id, chat: chat, author: author, text: text,
                     reaction: reactionTarget != nil, reactionTarget: reactionTarget)
    }

    guard let local = radio.selfNode, let envelope = PushProto(frame),
          let packet = envelope.message(2), let payload = packet.message(4),
          payload[1] == 1 else { return nil }
    let sender = packet[1]
    let destination = packet[2]
    guard sender != 0, sender != local, destination == local || destination == UInt32.max,
          let text = payload.string(2), !text.isEmpty else { return nil }
    let contact = "node:\(sender)"
    let chat = destination == UInt32.max ? "ch:\(packet[3])" : contact
    return Message(id: "mt:\(sender):\(destination):\(packet[6])", chat: chat,
                   author: radio.peers[contact] ?? String(format: "!%08x", sender),
                   text: text, reaction: payload[8] != 0,
                   reactionTarget: payload[7] > 0 ? String(payload[7]) : nil)
  }

  static func hex(_ bytes: ArraySlice<UInt8>) -> String {
    bytes.map { String(format: "%02x", $0) }.joined()
  }

  private static func meshCoreReaction(_ text: String, direct: Bool) -> String? {
    let lines = text.components(separatedBy: "\n")
    guard lines.count == 2 else { return nil }
    let hash = lines[1].lowercased().replacingOccurrences(of: "o", with: "0")
      .replacingOccurrences(of: "[il]", with: "1", options: .regularExpression)
    guard hash.count == 8, hash.range(of: #"^[0-9a-hjkmnp-tv-z]{8}$"#, options: .regularExpression) != nil
    else { return nil }

    var emoji = lines[0]
    var target = "mc:" + hash
    if !direct {
      let name = #"@\[[^\[\]]+\]"#
      if let prefix = emoji.range(of: "^" + name, options: .regularExpression) {
        target += ":" + String(emoji[prefix].dropFirst(2).dropLast())
        emoji.removeSubrange(prefix)
      } else if let suffix = emoji.range(of: name + "$", options: .regularExpression) {
        target += ":" + String(emoji[suffix].dropFirst(2).dropLast())
        emoji.removeSubrange(suffix)
      } else {
        return nil
      }
    }
    guard emoji.count == 1, emoji.range(
      of: #"\p{Extended_Pictographic}|\p{Regional_Indicator}|\x{20e3}"#,
      options: .regularExpression
    ) != nil else { return nil }
    return target
  }
}

// The PhoneAPI message envelope uses only scalar and length-delimited fields.
struct PushProto {
  private var numbers: [Int: UInt32] = [:]
  private(set) var bytes: [Int: [UInt8]] = [:]

  subscript(field: Int) -> UInt32 { numbers[field] ?? 0 }

  init?(_ data: [UInt8]) {
    var index = 0
    func varint() -> UInt64? {
      var result: UInt64 = 0
      for shift in stride(from: 0, to: 64, by: 7) {
        guard index < data.count else { return nil }
        let byte = data[index]
        index += 1
        guard shift != 63 || byte <= 1 else { return nil }
        result |= UInt64(byte & 0x7f) << shift
        if byte < 0x80 { return result }
      }
      return nil
    }
    while index < data.count {
      guard let tag = varint(), tag >= 8, tag <= UInt32.max else { return nil }
      let field = Int(tag >> 3)
      switch tag & 7 {
      case 0:
        guard let value = varint() else { return nil }
        numbers[field] = UInt32(truncatingIfNeeded: value)
      case 1:
        guard data.count - index >= 8 else { return nil }
        index += 8
      case 2:
        guard let length = varint(), length <= data.count - index else { return nil }
        let end = index + Int(length)
        bytes[field] = Array(data[index..<end])
        index = end
      case 5:
        guard data.count - index >= 4 else { return nil }
        numbers[field] = (0..<4).reduce(UInt32(0)) { $0 | UInt32(data[index + $1]) << ($1 * 8) }
        index += 4
      default:
        return nil
      }
    }
  }

  func message(_ field: Int) -> PushProto? { bytes[field].flatMap(PushProto.init) }

  func string(_ field: Int) -> String? {
    bytes[field].map { String(decoding: $0, as: UTF8.self) }
  }
}
