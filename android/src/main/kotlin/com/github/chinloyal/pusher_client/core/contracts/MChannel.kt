package com.github.chinloyal.pusher_client.core.contracts

import androidx.annotation.NonNull
import io.flutter.plugin.common.BinaryMessenger

interface MChannel {
    fun register (@NonNull messenger: BinaryMessenger)
}