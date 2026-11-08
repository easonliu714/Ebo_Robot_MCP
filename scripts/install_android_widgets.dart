import 'dart:io';

// Rebuilds native Android widget resources after `flutter create` on every CI run.
// Widget receivers only open a foreground Activity; no secrets or background
// microphone capture are ever embedded in or initiated by a RemoteViews widget.
void main() {
  const root = 'android/app/src/main';
  void put(String relative, String content) {
    final target = File('$root/$relative');
    target.parent.createSync(recursive: true);
    target.writeAsStringSync(content);
  }

  const pkg = 'kotlin/com/easonliu714/ebo_robot_mcp/';
  put('${pkg}MainActivity.kt', r'''
package com.easonliu714.ebo_robot_mcp

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ebo_robot_mcp/widget")
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
        if (target != null && target in setOf(
                "voice_qa", "voice_mcp", "quick_dock", "quick_patrol",
                "quick_pet", "quick_photo")) {
            channel?.invokeMethod("widgetAction", target)
            newIntent.removeExtra("ebo_widget_target")
        }
    }
}
''');

  put('${pkg}EboVoiceWidgets.kt', r'''
package com.easonliu714.ebo_robot_mcp

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

private fun widgetIntent(context: Context, widgetId: Int, mode: String): PendingIntent {
    val code = when (mode) {
        "voice_qa" -> 1; "voice_mcp" -> 2; "quick_dock" -> 3
        "quick_patrol" -> 4; "quick_pet" -> 5; "quick_photo" -> 6
        else -> 0
    }
    val intent = Intent(context, MainActivity::class.java).apply {
        flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        putExtra("ebo_widget_target", mode)
    }
    return PendingIntent.getActivity(context, widgetId * 10 + code, intent,
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
}

class EboVoiceQaWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) {
            val views = RemoteViews(context.packageName, R.layout.ebo_widget_qa)
            views.setOnClickPendingIntent(R.id.ebo_qa_action,
                widgetIntent(context, id, "voice_qa"))
            manager.updateAppWidget(id, views)
        }
    }
}
class EboVoiceMcpWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) {
            val views = RemoteViews(context.packageName, R.layout.ebo_widget_mcp)
            views.setOnClickPendingIntent(R.id.ebo_mcp_action,
                widgetIntent(context, id, "voice_mcp"))
            manager.updateAppWidget(id, views)
        }
    }
}
class EboVoiceDualWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) {
            val views = RemoteViews(context.packageName, R.layout.ebo_widget_dual)
            views.setOnClickPendingIntent(R.id.ebo_dual_qa,
                widgetIntent(context, id, "voice_qa"))
            views.setOnClickPendingIntent(R.id.ebo_dual_mcp,
                widgetIntent(context, id, "voice_mcp"))
            manager.updateAppWidget(id, views)
        }
    }
}
class EboQuickWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) {
            val views = RemoteViews(context.packageName, R.layout.ebo_widget_quick)
            views.setOnClickPendingIntent(R.id.ebo_quick_dock,
                widgetIntent(context, id, "quick_dock"))
            views.setOnClickPendingIntent(R.id.ebo_quick_patrol,
                widgetIntent(context, id, "quick_patrol"))
            views.setOnClickPendingIntent(R.id.ebo_quick_pet,
                widgetIntent(context, id, "quick_pet"))
            views.setOnClickPendingIntent(R.id.ebo_quick_photo,
                widgetIntent(context, id, "quick_photo"))
            manager.updateAppWidget(id, views)
        }
    }
}
''');
  put('res/values/ebo_widget_labels.xml', r'''
<resources>
  <string name="ebo_widget_qa_name">EBO 語音查詢</string>
  <string name="ebo_widget_mcp_name">EBO 語音控制</string>
  <string name="ebo_widget_dual_name">EBO 雙語音控制</string>
  <string name="ebo_widget_quick_name">EBO 快速指令</string>
</resources>
''');

  put('res/drawable/ebo_widget_outer.xml', r'''
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
  <corners android:radius="17dp"/>
  <solid android:color="#081E2D"/>
  <stroke android:width="1dp" android:color="#1ED9DB"/>
</shape>
''');
  put('res/drawable/ebo_widget_quick_bg.xml', r'''
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
  <corners android:radius="14dp"/>
  <gradient android:startColor="#033747" android:endColor="#0B3158" android:angle="0"/>
  <stroke android:width="1dp" android:color="#16AFB5"/>
</shape>
''');

  // Actual runtime appearance uses the approved art, not the default launcher.
  // Native TextView autosizing allows legible captions as cell sizes change.
  String voiceLayout(String clickId, String art, String label, String sub) => '''
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
  android:id="@+id/$clickId" android:layout_width="match_parent"
  android:layout_height="match_parent" android:padding="3dp"
  android:background="@drawable/ebo_widget_outer">
  <ImageView android:layout_width="match_parent" android:layout_height="match_parent"
    android:src="@drawable/$art" android:scaleType="fitXY"/>
  <LinearLayout android:layout_width="match_parent" android:layout_height="match_parent"
    android:orientation="vertical" android:gravity="center_vertical"
    android:paddingStart="10dp" android:paddingEnd="42dp">
    <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
      android:singleLine="true" android:gravity="start" android:text="🎙"
      android:textColor="#FFFFFF" android:textSize="13sp"/>
    <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
      android:singleLine="true" android:text="$label" android:textColor="#FFFFFF"
      android:textStyle="bold" android:textSize="13sp"
      android:autoSizeTextType="uniform" android:autoSizeMinTextSize="9sp"
      android:autoSizeMaxTextSize="13sp" android:autoSizeStepGranularity="1sp"/>
    <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
      android:singleLine="true" android:text="$sub" android:textColor="#CAECF5"
      android:textSize="10sp" android:autoSizeTextType="uniform"
      android:autoSizeMinTextSize="8sp" android:autoSizeMaxTextSize="10sp"
      android:autoSizeStepGranularity="1sp"/>
  </LinearLayout>
</FrameLayout>
''';
  put('res/layout/ebo_widget_qa.xml',
      voiceLayout('ebo_qa_action', 'ebo_widget_qa', '語音查詢', 'EBO 回覆'));
  put('res/layout/ebo_widget_mcp.xml',
      voiceLayout('ebo_mcp_action', 'ebo_widget_mcp', '語音控制', 'MCP 動作'));

  // 4x1 dual voice widget; each half is an independent clickable panel.
  put('res/layout/ebo_widget_dual.xml', r'''
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
  android:layout_width="match_parent" android:layout_height="match_parent"
  android:orientation="horizontal" android:padding="2dp"
  android:background="@drawable/ebo_widget_outer">
  <FrameLayout android:id="@+id/ebo_dual_qa" android:layout_width="0dp"
    android:layout_weight="1" android:layout_height="match_parent" android:padding="1dp">
    <ImageView android:layout_width="match_parent" android:layout_height="match_parent"
      android:src="@drawable/ebo_widget_qa" android:scaleType="fitXY"/>
    <TextView android:layout_width="match_parent" android:layout_height="match_parent"
      android:gravity="center_vertical|left" android:paddingStart="8dp"
      android:paddingEnd="32dp" android:text="🎙 語音查詢"
      android:textColor="#FFFFFF" android:textStyle="bold" android:textSize="12sp"
      android:autoSizeTextType="uniform" android:autoSizeMinTextSize="9sp"
      android:autoSizeMaxTextSize="12sp" android:autoSizeStepGranularity="1sp"/>
  </FrameLayout>
  <FrameLayout android:id="@+id/ebo_dual_mcp" android:layout_width="0dp"
    android:layout_weight="1" android:layout_height="match_parent" android:padding="1dp">
    <ImageView android:layout_width="match_parent" android:layout_height="match_parent"
      android:src="@drawable/ebo_widget_mcp" android:scaleType="fitXY"/>
    <TextView android:layout_width="match_parent" android:layout_height="match_parent"
      android:gravity="center_vertical|left" android:paddingStart="8dp"
      android:paddingEnd="32dp" android:text="🎙 語音控制"
      android:textColor="#FFFFFF" android:textStyle="bold" android:textSize="12sp"
      android:autoSizeTextType="uniform" android:autoSizeMinTextSize="9sp"
      android:autoSizeMaxTextSize="12sp" android:autoSizeStepGranularity="1sp"/>
  </FrameLayout>
</LinearLayout>
''');

  String shortcut(String id, String art, String title) => '''
  <FrameLayout android:id="@+id/$id" android:layout_width="0dp"
    android:layout_weight="1" android:layout_height="match_parent"
    android:layout_margin="2dp" android:background="@drawable/ebo_widget_quick_bg">
    <ImageView android:layout_width="match_parent" android:layout_height="match_parent"
      android:src="@drawable/$art" android:scaleType="fitXY"/>
    <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
      android:layout_gravity="bottom" android:gravity="center" android:paddingBottom="3dp"
      android:text="$title" android:textColor="#FFFFFF" android:textStyle="bold"
      android:textSize="11sp" android:autoSizeTextType="uniform"
      android:autoSizeMinTextSize="8sp" android:autoSizeMaxTextSize="11sp"
      android:autoSizeStepGranularity="1sp"/>
  </FrameLayout>
''';
  put('res/layout/ebo_widget_quick.xml', '''
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
  android:layout_width="match_parent" android:layout_height="match_parent"
  android:orientation="horizontal" android:padding="3dp"
  android:background="@drawable/ebo_widget_outer">
${shortcut('ebo_quick_dock', 'ebo_widget_dock', '回充')}
${shortcut('ebo_quick_patrol', 'ebo_widget_patrol', '巡邏')}
${shortcut('ebo_quick_pet', 'ebo_widget_pet', '找寵')}
${shortcut('ebo_quick_photo', 'ebo_widget_photo', '拍照')}
</LinearLayout>
''');

  void metadata(String name, String layout, String preview, bool wide) {
    put('res/xml/$name.xml', '''
<appwidget-provider xmlns:android="http://schemas.android.com/apk/res/android"
  android:minWidth="${wide ? 260 : 140}dp" android:minHeight="80dp"
  android:targetCellWidth="${wide ? 4 : 2}" android:targetCellHeight="1"
  android:updatePeriodMillis="0" android:initialLayout="@layout/$layout"
  android:previewLayout="@layout/$layout" android:previewImage="@drawable/$preview"
  android:resizeMode="horizontal|vertical" android:widgetCategory="home_screen"/>
''');
  }
  metadata('ebo_voice_qa_info', 'ebo_widget_qa', 'ebo_preview_qa', false);
  metadata('ebo_voice_mcp_info', 'ebo_widget_mcp', 'ebo_preview_mcp', false);
  metadata('ebo_voice_dual_info', 'ebo_widget_dual', 'ebo_preview_dual', true);
  metadata('ebo_voice_quick_info', 'ebo_widget_quick', 'ebo_preview_quick', true);

  final manifest = File('$root/AndroidManifest.xml');
  if (!manifest.existsSync()) {
    stderr.writeln('Run flutter create before install_android_widgets.dart');
    exitCode = 2;
    return;
  }
  var xml = manifest.readAsStringSync();
  if (!xml.contains('EboVoiceQaWidgetProvider')) {
    final receivers = <String, String>{
      'EboVoiceQaWidgetProvider': 'ebo_voice_qa_info',
      'EboVoiceMcpWidgetProvider': 'ebo_voice_mcp_info',
      'EboVoiceDualWidgetProvider': 'ebo_voice_dual_info',
      'EboQuickWidgetProvider': 'ebo_voice_quick_info',
    };
    final labels = <String, String>{
      'EboVoiceQaWidgetProvider': 'ebo_widget_qa_name',
      'EboVoiceMcpWidgetProvider': 'ebo_widget_mcp_name',
      'EboVoiceDualWidgetProvider': 'ebo_widget_dual_name',
      'EboQuickWidgetProvider': 'ebo_widget_quick_name',
    };
    final declarations = receivers.entries.map((entry) => '''
        <receiver android:name=".${entry.key}" android:exported="true"
            android:label="@string/${labels[entry.key]}">
          <intent-filter><action android:name="android.appwidget.action.APPWIDGET_UPDATE"/></intent-filter>
          <meta-data android:name="android.appwidget.provider"
            android:resource="@xml/${entry.value}"/>
        </receiver>
''').join();
    if (!xml.contains('</application>')) {
      stderr.writeln('Android manifest missing application element');
      exitCode = 2;
      return;
    }
    xml = xml.replaceFirst('</application>', '$declarations\n</application>');
    manifest.writeAsStringSync(xml);
  }
  stdout.writeln('Installed four native EBO widget providers, layouts and previews.');
}