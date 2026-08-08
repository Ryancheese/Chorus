package com.chorus.core.protocol

import org.json.JSONObject
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.charset.StandardCharsets

/**
 * Encodes/decodes control messages (JSON) and audio frames (binary).
 * Wire-compatible with Mac Swift and Windows C# ChorusCore.
 */
object MessageCodec {
    fun encodeControl(payload: ControlPayload): ByteArray {
        val root = JSONObject()
        root.put("type", payload.type.code)
        root.put("payload", encodePayloadBody(payload))
        return root.toString().toByteArray(StandardCharsets.UTF_8)
    }

    fun decodeControl(data: ByteArray): ControlPayload {
        val root = JSONObject(String(data, StandardCharsets.UTF_8))
        val type = MessageType.fromCode(root.getInt("type"))
        val payload = root.get("payload")
        return when (type) {
            MessageType.HELLO -> ControlPayload.Hello(decodeDeviceInfo(payload as JSONObject))
            MessageType.WELCOME -> ControlPayload.Welcome(decodeDeviceInfo(payload as JSONObject))
            MessageType.CLOCK_PING -> ControlPayload.ClockPing(decodeClockPing(payload as JSONObject))
            MessageType.CLOCK_PONG -> ControlPayload.ClockPong(decodeClockPong(payload as JSONObject))
            MessageType.PREPARE_SESSION ->
                ControlPayload.PrepareSession(decodePrepareSession(payload as JSONObject))
            MessageType.START_PLAYBACK ->
                ControlPayload.StartPlayback(decodeStartPlayback(payload as JSONObject))
            MessageType.STOP_PLAYBACK ->
                ControlPayload.StopPlayback((payload as JSONObject).getString("sessionID"))
            MessageType.AUDIO_CHANNEL_HELLO ->
                ControlPayload.AudioChannelHello((payload as JSONObject).optString("deviceID", ""))
            MessageType.STOP_ACKNOWLEDGED ->
                ControlPayload.StopAcknowledged((payload as JSONObject).getString("sessionID"))
            MessageType.CLOCK_OFFSET ->
                ControlPayload.ClockOffset((payload as Number).toDouble())
            MessageType.HEARTBEAT ->
                ControlPayload.Heartbeat((payload as JSONObject).optString("deviceID", ""))
            MessageType.GOODBYE ->
                ControlPayload.Goodbye((payload as JSONObject).optString("deviceID", ""))
            MessageType.AUDIO_CHUNK ->
                throw CodecException("audioChunk is binary, not JSON")
        }
    }

    /** Binary audio frame: `[1B type][4B headerLen BE][header JSON][pcm]`. */
    fun encodeAudioFrame(header: AudioChunkHeader, pcm: ByteArray): ByteArray {
        val headerJson = encodeAudioHeader(header).toString().toByteArray(StandardCharsets.UTF_8)
        val out = ByteArray(1 + 4 + headerJson.size + pcm.size)
        out[0] = MessageType.AUDIO_CHUNK.code.toByte()
        ByteBuffer.wrap(out, 1, 4).order(ByteOrder.BIG_ENDIAN).putInt(headerJson.size)
        System.arraycopy(headerJson, 0, out, 5, headerJson.size)
        System.arraycopy(pcm, 0, out, 5 + headerJson.size, pcm.size)
        return out
    }

    fun decodeAudioFrame(data: ByteArray): Pair<AudioChunkHeader, ByteArray> {
        if (data.size < 5 || data[0].toInt() and 0xFF != MessageType.AUDIO_CHUNK.code) {
            throw CodecException("Invalid frame: bad magic byte")
        }
        val headerLen = ByteBuffer.wrap(data, 1, 4).order(ByteOrder.BIG_ENDIAN).int
        val headerEnd = 5 + headerLen
        if (data.size < headerEnd || headerLen < 0) {
            throw CodecException("Invalid frame: truncated header")
        }
        val headerJson = String(data, 5, headerLen, StandardCharsets.UTF_8)
        val header = decodeAudioHeader(JSONObject(headerJson))
        val pcm = data.copyOfRange(headerEnd, data.size)
        return header to pcm
    }

    private fun encodePayloadBody(payload: ControlPayload): Any =
        when (payload) {
            is ControlPayload.Hello -> encodeDeviceInfo(payload.info)
            is ControlPayload.Welcome -> encodeDeviceInfo(payload.info)
            is ControlPayload.ClockPing -> encodeClockPing(payload.ping)
            is ControlPayload.ClockPong -> encodeClockPong(payload.pong)
            is ControlPayload.PrepareSession -> encodePrepareSession(payload.session)
            is ControlPayload.StartPlayback -> encodeStartPlayback(payload.start)
            is ControlPayload.StopPlayback -> JSONObject().put("sessionID", payload.sessionId)
            is ControlPayload.AudioChannelHello -> JSONObject().put("deviceID", payload.deviceId)
            is ControlPayload.StopAcknowledged -> JSONObject().put("sessionID", payload.sessionId)
            is ControlPayload.ClockOffset -> payload.seconds
            is ControlPayload.Heartbeat -> JSONObject().put("deviceID", payload.deviceId)
            is ControlPayload.Goodbye -> JSONObject().put("deviceID", payload.deviceId)
        }

    private fun encodeDeviceInfo(info: DeviceInfo): JSONObject =
        JSONObject()
            .put("id", info.id)
            .put("name", info.name)
            .put("role", info.role.wire)
            .put("protocolVersion", info.protocolVersion)

    private fun decodeDeviceInfo(obj: JSONObject): DeviceInfo =
        DeviceInfo(
            id = obj.getString("id"),
            name = obj.getString("name"),
            role = DeviceRole.fromWire(obj.getString("role")),
            protocolVersion = obj.optInt("protocolVersion", SyncProtocol.VERSION),
        )

    private fun encodeClockPing(ping: ClockPingData): JSONObject =
        JSONObject()
            .put("pingID", ping.pingId)
            .put("hostSendTime", ping.hostSendTime)

    private fun decodeClockPing(obj: JSONObject): ClockPingData =
        ClockPingData(
            pingId = obj.getString("pingID"),
            hostSendTime = obj.getDouble("hostSendTime"),
        )

    private fun encodeClockPong(pong: ClockPongData): JSONObject =
        JSONObject()
            .put("pingID", pong.pingId)
            .put("hostSendTime", pong.hostSendTime)
            .put("speakerReceiveTime", pong.speakerReceiveTime)
            .put("speakerSendTime", pong.speakerSendTime)

    private fun decodeClockPong(obj: JSONObject): ClockPongData =
        ClockPongData(
            pingId = obj.getString("pingID"),
            hostSendTime = obj.getDouble("hostSendTime"),
            speakerReceiveTime = obj.getDouble("speakerReceiveTime"),
            speakerSendTime = obj.getDouble("speakerSendTime"),
        )

    private fun encodePrepareSession(session: PrepareSessionData): JSONObject =
        JSONObject()
            .put("sessionID", session.sessionId)
            .put("sampleRate", session.sampleRate)
            .put("channels", session.channels)
            .put("title", session.title)

    private fun decodePrepareSession(obj: JSONObject): PrepareSessionData =
        PrepareSessionData(
            sessionId = obj.getString("sessionID"),
            sampleRate = obj.getDouble("sampleRate"),
            channels = obj.getInt("channels"),
            title = obj.getString("title"),
        )

    private fun encodeStartPlayback(start: StartPlaybackData): JSONObject =
        JSONObject()
            .put("sessionID", start.sessionId)
            .put("hostPlayAt", start.hostPlayAt)
            .put("leadTime", start.leadTime)

    private fun decodeStartPlayback(obj: JSONObject): StartPlaybackData =
        StartPlaybackData(
            sessionId = obj.getString("sessionID"),
            hostPlayAt = obj.getDouble("hostPlayAt"),
            leadTime = obj.optDouble("leadTime", SyncProtocol.DEFAULT_LEAD_TIME),
        )

    private fun encodeAudioHeader(header: AudioChunkHeader): JSONObject =
        JSONObject()
            .put("sessionID", header.sessionId)
            .put("sequence", header.sequence)
            .put("sampleIndex", header.sampleIndex)
            .put("sampleCount", header.sampleCount)
            .put("hostPlayAt", header.hostPlayAt)

    private fun decodeAudioHeader(obj: JSONObject): AudioChunkHeader =
        AudioChunkHeader(
            sessionId = obj.getString("sessionID"),
            sequence = obj.getLong("sequence"),
            sampleIndex = obj.getLong("sampleIndex"),
            sampleCount = obj.getLong("sampleCount"),
            hostPlayAt = obj.getDouble("hostPlayAt"),
        )
}
