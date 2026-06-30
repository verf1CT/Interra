package ru.interra.lk_interra

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity (а не FlutterActivity) требуется пакету local_auth
// для отображения системного диалога биометрии.
class MainActivity : FlutterFragmentActivity()
