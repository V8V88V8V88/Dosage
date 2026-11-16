#pragma once

#include <glib.h>

gboolean dosage_android_init               (void);
gboolean dosage_android_can_notify         (void);
gboolean dosage_android_can_schedule_exact (void);
void     dosage_android_request_permissions (void);
/* Returns TRUE if scheduled exactly, FALSE if inexact or failed. */
gboolean dosage_android_schedule           (gint id, gint64 trigger_at_ms,
                                            const char *title, const char *body);
void     dosage_android_cancel             (gint id);
/* Device UTC offset in seconds at the given instant (GLib alone would use UTC). */
gint     dosage_android_utc_offset_seconds (gint64 at_ms);
/* App cache directory (Context.getCacheDir()), newly allocated. */
char    *dosage_android_get_cache_dir      (void);
/* Battery optimisation exemption ("Unrestricted"); OEMs like ColorOS freeze apps otherwise. */
gboolean dosage_android_is_battery_unrestricted     (void);
void     dosage_android_request_battery_unrestricted (void);
/* Locale info GLib can't provide on Android. */
gboolean dosage_android_is_24_hour         (void);
gint     dosage_android_first_day_of_week  (void);
/* Haptic feedback: 0 = tick (selection), 1 = click (action), 2 = heavy click. */
void     dosage_android_haptic             (gint kind);
/* Device language as a POSIX locale (e.g. "pt_BR"), newly allocated. */
char    *dosage_android_get_locale         (void);
