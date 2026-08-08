package com.chorus.core.network

import java.net.Inet4Address
import java.net.NetworkInterface

object LocalAddress {
    fun primaryIPv4(): String? {
        val interfaces = NetworkInterface.getNetworkInterfaces()?.toList().orEmpty()
        for (ni in interfaces) {
            if (!ni.isUp || ni.isLoopback) continue
            val name = ni.name.lowercase()
            if (name.startsWith("docker") ||
                name.startsWith("veth") ||
                name.startsWith("dummy") ||
                name.startsWith("rmnet")
            ) {
                continue
            }
            for (addr in ni.inetAddresses) {
                if (addr is Inet4Address && !addr.isLoopbackAddress) {
                    return addr.hostAddress
                }
            }
        }
        return null
    }
}
