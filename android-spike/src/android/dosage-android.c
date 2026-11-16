/* JNI bridge from the GTK thread to io.github.diegopvlk.dosage.android.DosageAlarms. */

#include "dosage-android.h"

#include <jni.h>
#include <glib.h>

#define ALARMS_CLASS "io.github.diegopvlk.dosage.android.DosageAlarms"

static JavaVM *vm;
static jobject app_context;  /* global ref: android.app.Application */
static jclass alarms_class;  /* global ref */

static JNIEnv *
get_env (void)
{
  JNIEnv *env = NULL;

  if (vm == NULL)
    {
      jsize n = 0;
      if (JNI_GetCreatedJavaVMs (&vm, 1, &n) != JNI_OK || n < 1)
        {
          g_warning ("dosage-android: no Java VM");
          vm = NULL;
          return NULL;
        }
    }

  /* The GTK thread is already attached by the GTK runtime. */
  if ((*vm)->GetEnv (vm, (void **) &env, JNI_VERSION_1_6) == JNI_EDETACHED)
    (*vm)->AttachCurrentThread (vm, &env, NULL);

  return env;
}

static gboolean
check_exception (JNIEnv *env, const char *what)
{
  if (!(*env)->ExceptionCheck (env))
    return FALSE;
  g_warning ("dosage-android: Java exception in %s", what);
  (*env)->ExceptionDescribe (env);
  (*env)->ExceptionClear (env);
  return TRUE;
}

gboolean
dosage_android_init (void)
{
  JNIEnv *env = get_env ();
  if (env == NULL)
    return FALSE;
  if (alarms_class != NULL)
    return TRUE;

  /* Application context via ActivityThread.currentApplication(). Framework classes
   * resolve from a native thread; app classes need the app's own ClassLoader. */
  jclass at = (*env)->FindClass (env, "android/app/ActivityThread");
  jmethodID current_app = (*env)->GetStaticMethodID (env, at, "currentApplication",
                                                     "()Landroid/app/Application;");
  jobject app = (*env)->CallStaticObjectMethod (env, at, current_app);
  if (check_exception (env, "currentApplication") || app == NULL)
    return FALSE;

  jclass ctx_class = (*env)->FindClass (env, "android/content/Context");
  jmethodID get_cl = (*env)->GetMethodID (env, ctx_class, "getClassLoader",
                                          "()Ljava/lang/ClassLoader;");
  jobject loader = (*env)->CallObjectMethod (env, app, get_cl);

  jclass cl_class = (*env)->FindClass (env, "java/lang/ClassLoader");
  jmethodID load_class = (*env)->GetMethodID (env, cl_class, "loadClass",
                                              "(Ljava/lang/String;)Ljava/lang/Class;");
  jstring name = (*env)->NewStringUTF (env, ALARMS_CLASS);
  jclass klass = (*env)->CallObjectMethod (env, loader, load_class, name);
  if (check_exception (env, "loadClass") || klass == NULL)
    return FALSE;

  app_context = (*env)->NewGlobalRef (env, app);
  alarms_class = (*env)->NewGlobalRef (env, klass);

  jmethodID init = (*env)->GetStaticMethodID (env, alarms_class, "init",
                                              "(Landroid/content/Context;)V");
  (*env)->CallStaticVoidMethod (env, alarms_class, init, app_context);
  if (check_exception (env, "init"))
    return FALSE;

  (*env)->DeleteLocalRef (env, name);
  (*env)->DeleteLocalRef (env, loader);
  (*env)->DeleteLocalRef (env, klass);
  (*env)->DeleteLocalRef (env, app);
  return TRUE;
}

static gboolean
call_bool (const char *method)
{
  JNIEnv *env = get_env ();
  if (env == NULL || alarms_class == NULL)
    return FALSE;
  jmethodID m = (*env)->GetStaticMethodID (env, alarms_class, method,
                                           "(Landroid/content/Context;)Z");
  jboolean r = (*env)->CallStaticBooleanMethod (env, alarms_class, m, app_context);
  return !check_exception (env, method) && r;
}

gboolean
dosage_android_can_notify (void)
{
  return call_bool ("canNotify");
}

gboolean
dosage_android_can_schedule_exact (void)
{
  return call_bool ("canScheduleExact");
}

void
dosage_android_request_permissions (void)
{
  JNIEnv *env = get_env ();
  if (env == NULL || alarms_class == NULL)
    return;
  jmethodID m = (*env)->GetStaticMethodID (env, alarms_class, "requestPermissions",
                                           "(Landroid/content/Context;)V");
  (*env)->CallStaticVoidMethod (env, alarms_class, m, app_context);
  check_exception (env, "requestPermissions");
}

gboolean
dosage_android_schedule (gint id, gint64 trigger_at_ms, const char *title, const char *body)
{
  JNIEnv *env = get_env ();
  if (env == NULL || alarms_class == NULL)
    return FALSE;
  jmethodID m = (*env)->GetStaticMethodID (env, alarms_class, "schedule",
                                           "(Landroid/content/Context;IJLjava/lang/String;Ljava/lang/String;)Z");
  jstring jtitle = (*env)->NewStringUTF (env, title);
  jstring jbody = (*env)->NewStringUTF (env, body);
  jboolean exact = (*env)->CallStaticBooleanMethod (env, alarms_class, m, app_context,
                                                    (jint) id, (jlong) trigger_at_ms,
                                                    jtitle, jbody);
  (*env)->DeleteLocalRef (env, jtitle);
  (*env)->DeleteLocalRef (env, jbody);
  if (check_exception (env, "schedule"))
    return FALSE;
  return exact;
}

void
dosage_android_cancel (gint id)
{
  JNIEnv *env = get_env ();
  if (env == NULL || alarms_class == NULL)
    return;
  jmethodID m = (*env)->GetStaticMethodID (env, alarms_class, "cancel",
                                           "(Landroid/content/Context;I)V");
  (*env)->CallStaticVoidMethod (env, alarms_class, m, app_context, (jint) id);
  check_exception (env, "cancel");
}

gint
dosage_android_utc_offset_seconds (gint64 at_ms)
{
  /* GLib has no Android tzdata support (no /etc/localtime), so local time would be UTC.
   * Ask java.util.TimeZone for the device offset (DST-aware) at the given instant. */
  JNIEnv *env = get_env ();
  if (env == NULL)
    return 0;
  jclass tz_class = (*env)->FindClass (env, "java/util/TimeZone");
  jmethodID get_default = (*env)->GetStaticMethodID (env, tz_class, "getDefault",
                                                     "()Ljava/util/TimeZone;");
  jmethodID get_offset = (*env)->GetMethodID (env, tz_class, "getOffset", "(J)I");
  jobject tz = (*env)->CallStaticObjectMethod (env, tz_class, get_default);
  jint offset_ms = (*env)->CallIntMethod (env, tz, get_offset, (jlong) at_ms);
  (*env)->DeleteLocalRef (env, tz);
  (*env)->DeleteLocalRef (env, tz_class);
  if (check_exception (env, "TimeZone.getOffset"))
    return 0;
  return offset_ms / 1000;
}

char *
dosage_android_get_cache_dir (void)
{
  /* Context.getCacheDir() via ActivityThread.currentApplication(). Needs only
   * framework classes, so it works before dosage_android_init(). */
  JNIEnv *env = get_env ();
  if (env == NULL)
    return NULL;
  jclass at = (*env)->FindClass (env, "android/app/ActivityThread");
  jmethodID current_app = (*env)->GetStaticMethodID (env, at, "currentApplication",
                                                     "()Landroid/app/Application;");
  jobject app = (*env)->CallStaticObjectMethod (env, at, current_app);
  if (check_exception (env, "currentApplication") || app == NULL)
    return NULL;
  jclass ctx_class = (*env)->FindClass (env, "android/content/Context");
  jmethodID get_cache = (*env)->GetMethodID (env, ctx_class, "getCacheDir", "()Ljava/io/File;");
  jobject file = (*env)->CallObjectMethod (env, app, get_cache);
  jclass file_class = (*env)->FindClass (env, "java/io/File");
  jmethodID get_path = (*env)->GetMethodID (env, file_class, "getAbsolutePath", "()Ljava/lang/String;");
  jstring path = (*env)->CallObjectMethod (env, file, get_path);
  if (check_exception (env, "getCacheDir") || path == NULL)
    return NULL;
  const char *utf = (*env)->GetStringUTFChars (env, path, NULL);
  char *ret = g_strdup (utf);
  (*env)->ReleaseStringUTFChars (env, path, utf);
  return ret;
}

gboolean
dosage_android_is_battery_unrestricted (void)
{
  return call_bool ("isBatteryUnrestricted");
}

void
dosage_android_request_battery_unrestricted (void)
{
  JNIEnv *env = get_env ();
  if (env == NULL || alarms_class == NULL)
    return;
  jmethodID m = (*env)->GetStaticMethodID (env, alarms_class, "requestBatteryUnrestricted",
                                           "(Landroid/content/Context;)V");
  (*env)->CallStaticVoidMethod (env, alarms_class, m, app_context);
  check_exception (env, "requestBatteryUnrestricted");
}
