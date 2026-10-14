package com.everuptodate.ever_up_to_date

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.mockito.Mockito
import kotlin.test.Test

internal class EverUpToDatePluginTest {
    @Test
    fun installWithoutAttachedEngineReportsNoContext() {
        val plugin = EverUpToDatePlugin()
        val result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(MethodCall("installApk", mapOf("filePath" to "/tmp/update.apk")), result)
        Mockito.verify(result).error("NO_CONTEXT", "Application context is null", null)
    }

    @Test
    fun permissionWithoutAttachedEngineReportsNoContext() {
        val plugin = EverUpToDatePlugin()
        val result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(MethodCall("canRequestPackageInstalls", null), result)
        Mockito.verify(result).error("NO_CONTEXT", "Application context is null", null)
    }
}
