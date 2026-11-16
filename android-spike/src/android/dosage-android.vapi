[CCode (cheader_filename = "dosage-android.h", lower_case_cprefix = "dosage_android_")]
namespace DosageAndroid {
	public bool init ();
	public bool can_notify ();
	public bool can_schedule_exact ();
	public void request_permissions ();
	public bool schedule (int id, int64 trigger_at_ms, string title, string body);
	public void cancel (int id);
	public int utc_offset_seconds (int64 at_ms);
	public string? get_cache_dir ();
	public bool is_battery_unrestricted ();
	public void request_battery_unrestricted ();
}
