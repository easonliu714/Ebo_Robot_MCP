import 'dart:io';

// Run after flutter create in CI. No credentials or API keys are embedded.
void main() {
  const root = 'android/app/src/main';
  void put(String path, String content) {
    final f = File('$root/$path');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(content);
  }

  const pkg = 'kotlin/com/easonliu714/ebo_robot_mcp/';
  put(pkg + 'MainActivity.kt', r'''
package com.easonliu714.ebo_robot_mcp
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "ebo_robot_mcp/widget")
        channel!!.setMethodCallHandler { call, result ->
            if (call.method == "getInitialWidgetTarget") {
                val target = intent?.getStringExtra("ebo_widget_target")
                intent?.removeExtra("ebo_widget_target")
                result.success(target)
            } else result.notImplemented()
        }
    }
    override fun onNewIntent(newIntent: Intent) {
        super.onNewIntent(newIntent)
        setIntent(newIntent)
        val target = newIntent.getStringExtra("ebo_widget_target")
        if (target == "voice_qa" || target == "voice_mcp") {
            channel?.invokeMethod("widgetAction", target)
            newIntent.removeExtra("ebo_widget_target")
        }
    }
}
''');

  put(pkg + 'EboVoiceWidgets.kt', r'''
package com.easonliu714.ebo_robot_mcp
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

private fun openVoice(context: Context, id: Int, mode: String): PendingIntent {
    val launch = Intent(context, MainActivity::class.java).apply {
        flags = Intent.FLAG_ACTIVITY_NEW_TASK or
            Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        putExtra("ebo_widget_target", mode)
    }
    return PendingIntent.getActivity(context,
        id * 10 + if (mode == "voice_qa") 1 else 2, launch,
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
}
class EboVoiceQaWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) {
            val views = RemoteViews(context.packageName, R.layout.ebo_widget_qa)
            views.setOnClickPendingIntent(R.id.ebo_qa_action,
                openVoice(context, id, "voice_qa"))
            manager.updateAppWidget(id, views)
        }
    }
}
class EboVoiceMcpWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) {
            val views = RemoteViews(context.packageName, R.layout.ebo_widget_mcp)
            views.setOnClickPendingIntent(R.id.ebo_mcp_action,
                openVoice(context, id, "voice_mcp"))
            manager.updateAppWidget(id, views)
        }
    }
}
class EboVoiceDualWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) {
            val views = RemoteViews(context.packageName, R.layout.ebo_widget_dual)
            views.setOnClickPendingIntent(R.id.ebo_dual_qa,
                openVoice(context, id, "voice_qa"))
            views.setOnClickPendingIntent(R.id.ebo_dual_mcp,
                openVoice(context, id, "voice_mcp"))
            manager.updateAppWidget(id, views)
        }
    }
}
''');

  put('res/drawable/ebo_widget_bg.xml', r'''
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
  <corners android:radius="18dp"/>
  <solid android:color="#0C2635"/>
  <stroke android:width="1dp" android:color="#3C929E"/>
</shape>
''');
  put('res/drawable/ebo_widget_button_qa.xml', r'''
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
  <corners android:radius="12dp"/>
  <solid android:color="#116B83"/>
</shape>
''');
  put('res/drawable/ebo_widget_button_mcp.xml', r'''
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
  <corners android:radius="12dp"/>
  <solid android:color="#42578C"/>
</shape>
''');

  String layout(String id, String background, String text) => '''
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
  android:layout_width="match_parent" android:layout_height="match_parent"
  android:padding="8dp" android:orientation="vertical"
  android:background="@drawable/ebo_widget_bg">
  <TextView android:id="@+id/$id"
    android:layout_width="match_parent" android:layout_height="match_parent"
    android:padding="8dp" android:gravity="center"
    android:background="@drawable/$background"
    android:text="$text" android:textSize="15sp"
    android:textStyle="bold" android:textColor="#FFFFFFFF"/>
</LinearLayout>
''';
  put('res/layout/ebo_widget_qa.xml',
      layout('ebo_qa_action', 'ebo_widget_button_qa',
          '🎙 語音查詢&#10;EBO 語音回覆'));
  put('res/layout/ebo_widget_mcp.xml',
      layout('ebo_mcp_action', 'ebo_widget_button_mcp',
          '🎤 語音指令&#10;MCP 控制'));
  put('res/layout/ebo_widget_dual.xml', r'''
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
  android:layout_width="match_parent" android:layout_height="match_parent"
  android:padding="8dp" android:orientation="horizontal"
  android:background="@drawable/ebo_widget_bg">
  <TextView android:id="@+id/ebo_dual_qa"
    android:layout_width="0dp" android:layout_weight="1"
    android:layout_height="match_parent" android:layout_marginEnd="4dp"
    android:padding="6dp" android:gravity="center"
    android:background="@drawable/ebo_widget_button_qa"
    android:text="🎙 語音查詢&#10;EBO 回覆" android:textSize="13sp"
    android:textStyle="bold" android:textColor="#FFFFFFFF"/>
  <TextView android:id="@+id/ebo_dual_mcp"
    android:layout_width="0dp" android:layout_weight="1"
    android:layout_height="match_parent" android:layout_marginStart="4dp"
    android:padding="6dp" android:gravity="center"
    android:background="@drawable/ebo_widget_button_mcp"
    android:text="🎤 語音指令&#10;MCP 控制" android:textSize="13sp"
    android:textStyle="bold" android:textColor="#FFFFFFFF"/>
</LinearLayout>
''');

  void metadata(String name, String layoutName, bool dual) {
    final width = dual ? '260dp' : '140dp';
    final columns = dual ? '4' : '2';
    put('res/xml/$name.xml', '''
<appwidget-provider xmlns:android="http://schemas.android.com/apk/res/android"
  android:minWidth="$width" android:minHeight="80dp"
  android:targetCellWidth="$columns" android:targetCellHeight="1"
  android:updatePeriodMillis="0" android:initialLayout="@layout/$layoutName"
  android:resizeMode="horizontal|vertical"
  android:widgetCategory="home_screen"/>
''');
  }
  metadata('ebo_voice_qa_info', 'ebo_widget_qa', false);
  metadata('ebo_voice_mcp_info', 'ebo_widget_mcp', false);
  metadata('ebo_voice_dual_info', 'ebo_widget_dual', true);

  final manifest = File('$root/AndroidManifest.xml');
  if (!manifest.existsSync()) {
    stderr.writeln('Run flutter create first'); exitCode = 2; return;
  }
  var xml = manifest.readAsStringSync();
  if (!xml.contains('EboVoiceQaWidgetProvider')) {
    const receivers = r'''
        <receiver android:name=".EboVoiceQaWidgetProvider" android:exported="true">
          <intent-filter><action android:name="android.appwidget.action.APPWIDGET_UPDATE"/></intent-filter>
          <meta-data android:name="android.appwidget.provider" android:resource="@xml/ebo_voice_qa_info"/>
        </receiver>
        <receiver android:name=".EboVoiceMcpWidgetProvider" android:exported="true">
          <intent-filter><action android:name="android.appwidget.action.APPWIDGET_UPDATE"/></intent-filter>
          <meta-data android:name="android.appwidget.provider" android:resource="@xml/ebo_voice_mcp_info"/>
        </receiver>
        <receiver android:name=".EboVoiceDualWidgetProvider" android:exported="true">
          <intent-filter><action android:name="android.appwidget.action.APPWIDGET_UPDATE"/></intent-filter>
          <meta-data android:name="android.appwidget.provider" android:resource="@xml/ebo_voice_dual_info"/>
        </receiver>
''';
    if (!xml.contains('</application>')) {
      stderr.writeln('Missing application element'); exitCode = 2; return;
    }
    xml = xml.replaceFirst('</application>', receivers + '\n</application>');
    manifest.writeAsStringSync(xml);
  }
  stdout.writeln('Installed EBO voice home widgets');
}
