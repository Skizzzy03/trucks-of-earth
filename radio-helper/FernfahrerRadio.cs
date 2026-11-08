// Fernfahrer-Radio: the cab radio of the Trucks of Earth (BeamNG.drive mod fernfahrer_karriere).
// Three sources, picked in the game's cab app:
//   radio   – internet stations, decoded here (Windows Media Foundation) and played on the default speakers through
//             the car-speaker filter: clear in the cab, muffled from outside, fading on foot. Nothing to set up.
//   spotify – Spotify (or another player) as it is, on the normal speakers: the helper sets that program's volume in
//             the Windows mixer (full in the cab, quieter outside, fading on foot, down while the navi speaks), sends
//             the media keys (play/pause, next, previous) and reads the song from Spotify's window title.
//   line    – the old way with the filter: a player set to the output "Steam Streaming Speakers", taken from there.
// The game writes 4x a second %LOCALAPPDATA%\BeamNG\BeamNG.drive\current\settings\fernfahrer\radio_state.json
//   { t, mode = cab|outside|walk|off, dist, vol, duck, src, url, cmd, seq }
// and reads the heartbeat radio_helper.json { t, status, level, src, title, ok }. A tray icon ends the helper.
// Build: csc /target:winexe /out:Fernfahrer-Radio.exe FernfahrerRadio.cs   (.NET Framework 4)
// Checks: Fernfahrer-Radio.exe --probe <url>  (decodes 4 s, prints the level)   --sessions  (lists the mixer's programs)
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Forms;
using System.Drawing;

namespace FernfahrerRadio
{
    // --- WASAPI (Core Audio) ------------------------------------------------------------------------------------------
    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDeviceEnumeratorCo { }

    [Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceEnumerator
    {
        [PreserveSig] int EnumAudioEndpoints(int dataFlow, int stateMask, out IMMDeviceCollection devices);
        [PreserveSig] int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice device);
        [PreserveSig] int GetDevice([MarshalAs(UnmanagedType.LPWStr)] string id, out IMMDevice device);
        [PreserveSig] int RegisterEndpointNotificationCallback(IntPtr client);
        [PreserveSig] int UnregisterEndpointNotificationCallback(IntPtr client);
    }
    [Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceCollection
    {
        [PreserveSig] int GetCount(out int count);
        [PreserveSig] int Item(int index, out IMMDevice device);
    }
    [Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDevice
    {
        [PreserveSig] int Activate(ref Guid iid, int clsCtx, IntPtr activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object iface);
        [PreserveSig] int OpenPropertyStore(int access, out IPropertyStore store);
        [PreserveSig] int GetId([MarshalAs(UnmanagedType.LPWStr)] out string id);
        [PreserveSig] int GetState(out int state);
    }
    [StructLayout(LayoutKind.Sequential)] struct PropertyKey { public Guid fmtid; public int pid; }
    [StructLayout(LayoutKind.Sequential)] struct PropVariant { public short vt; public short r1, r2, r3; public IntPtr p; public IntPtr p2; }
    [Guid("886d8eeb-8cf2-4446-8d02-cdba1dbdcf99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IPropertyStore
    {
        [PreserveSig] int GetCount(out int count);
        [PreserveSig] int GetAt(int i, out PropertyKey key);
        [PreserveSig] int GetValue(ref PropertyKey key, out PropVariant value);
        [PreserveSig] int SetValue(ref PropertyKey key, ref PropVariant value);
        [PreserveSig] int Commit();
    }
    [Guid("1CB9AD4C-DBFA-4c32-B178-C2F568A703B2"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioClient
    {
        [PreserveSig] int Initialize(int shareMode, int streamFlags, long bufferDuration, long periodicity, IntPtr format, IntPtr sessionGuid);
        [PreserveSig] int GetBufferSize(out int frames);
        [PreserveSig] int GetStreamLatency(out long latency);
        [PreserveSig] int GetCurrentPadding(out int frames);
        [PreserveSig] int IsFormatSupported(int shareMode, IntPtr format, out IntPtr closest);
        [PreserveSig] int GetMixFormat(out IntPtr format);
        [PreserveSig] int GetDevicePeriod(out long def, out long min);
        [PreserveSig] int Start();
        [PreserveSig] int Stop();
        [PreserveSig] int Reset();
        [PreserveSig] int SetEventHandle(IntPtr h);
        [PreserveSig] int GetService(ref Guid iid, [MarshalAs(UnmanagedType.IUnknown)] out object service);
    }
    [Guid("C8ADBD64-E71E-48a0-A4DE-185C395CD317"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioCaptureClient
    {
        [PreserveSig] int GetBuffer(out IntPtr data, out int frames, out int flags, out long devPos, out long qpcPos);
        [PreserveSig] int ReleaseBuffer(int frames);
        [PreserveSig] int GetNextPacketSize(out int frames);
    }
    [Guid("F294ACFC-3146-4483-A7BF-ADDCA7C260E2"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioRenderClient
    {
        [PreserveSig] int GetBuffer(int frames, out IntPtr data);
        [PreserveSig] int ReleaseBuffer(int frames, int flags);
    }

    // --- the Windows mixer's programs (a player's own volume) -------------------------------------------------------
    [Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioSessionManager2
    {
        [PreserveSig] int GetAudioSessionControl(IntPtr guid, int flags, out IntPtr control);
        [PreserveSig] int GetSimpleAudioVolume(IntPtr guid, int flags, out IntPtr volume);
        [PreserveSig] int GetSessionEnumerator(out IAudioSessionEnumerator e);
        [PreserveSig] int RegisterSessionNotification(IntPtr n);
        [PreserveSig] int UnregisterSessionNotification(IntPtr n);
        [PreserveSig] int RegisterDuckNotification(IntPtr id, IntPtr n);
        [PreserveSig] int UnregisterDuckNotification(IntPtr n);
    }
    [Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioSessionEnumerator
    {
        [PreserveSig] int GetCount(out int n);
        [PreserveSig] int GetSession(int i, [MarshalAs(UnmanagedType.IUnknown)] out object s);
    }
    [Guid("bfb7ff88-7239-4fc9-8fa2-07c950be9c6d"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioSessionControl2
    {
        [PreserveSig] int GetState(out int state);
        [PreserveSig] int GetDisplayName(out IntPtr name);
        [PreserveSig] int SetDisplayName(IntPtr name, IntPtr ctx);
        [PreserveSig] int GetIconPath(out IntPtr path);
        [PreserveSig] int SetIconPath(IntPtr path, IntPtr ctx);
        [PreserveSig] int GetGroupingParam(out Guid g);
        [PreserveSig] int SetGroupingParam(IntPtr g, IntPtr ctx);
        [PreserveSig] int RegisterAudioSessionNotification(IntPtr n);
        [PreserveSig] int UnregisterAudioSessionNotification(IntPtr n);
        [PreserveSig] int GetSessionIdentifier(out IntPtr id);
        [PreserveSig] int GetSessionInstanceIdentifier(out IntPtr id);
        [PreserveSig] int GetProcessId(out int pid);
        [PreserveSig] int IsSystemSoundsSession();
        [PreserveSig] int SetDuckingPreference(int optOut);
    }
    [Guid("87CE5498-68D6-44E5-9215-6DA47EF883D8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface ISimpleAudioVolume
    {
        [PreserveSig] int SetMasterVolume(float level, IntPtr ctx);
        [PreserveSig] int GetMasterVolume(out float level);
        [PreserveSig] int SetMute(int mute, IntPtr ctx);
        [PreserveSig] int GetMute(out int mute);
    }

    // --- Media Foundation: a stream from the internet decoded to float PCM ------------------------------------------
    // (IMFAttributes has 30 methods; the derived interfaces repeat them – only the slot order matters, the unused ones
    // are placeholders never called)
    [Guid("44ae0fa8-ea31-4109-8d2e-4cae4997c555"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMFMediaType
    {
        [PreserveSig] int GetItem(); [PreserveSig] int GetItemType(); [PreserveSig] int CompareItem(); [PreserveSig] int Compare();
        [PreserveSig] int GetUINT32(ref Guid key, out int value);
        [PreserveSig] int GetUINT64(); [PreserveSig] int GetDouble(); [PreserveSig] int GetGUID(); [PreserveSig] int GetStringLength();
        [PreserveSig] int GetString(); [PreserveSig] int GetAllocatedString(); [PreserveSig] int GetBlobSize(); [PreserveSig] int GetBlob();
        [PreserveSig] int GetAllocatedBlob(); [PreserveSig] int GetUnknown(); [PreserveSig] int SetItem(); [PreserveSig] int DeleteItem();
        [PreserveSig] int DeleteAllItems();
        [PreserveSig] int SetUINT32(ref Guid key, int value);
        [PreserveSig] int SetUINT64(); [PreserveSig] int SetDouble();
        [PreserveSig] int SetGUID(ref Guid key, ref Guid value);
        [PreserveSig] int SetString(); [PreserveSig] int SetBlob(); [PreserveSig] int SetUnknown(); [PreserveSig] int LockStore();
        [PreserveSig] int UnlockStore(); [PreserveSig] int GetCount(); [PreserveSig] int GetItemByIndex(); [PreserveSig] int CopyAllItems();
        // IMFMediaType
        [PreserveSig] int GetMajorType(); [PreserveSig] int IsCompressedFormat(); [PreserveSig] int IsEqual();
        [PreserveSig] int GetRepresentation(); [PreserveSig] int FreeRepresentation();
    }
    [Guid("c40a00f2-b93a-4d80-ae8c-5a1c634f58e4"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMFSample
    {
        [PreserveSig] int A0(); [PreserveSig] int A1(); [PreserveSig] int A2(); [PreserveSig] int A3(); [PreserveSig] int A4();
        [PreserveSig] int A5(); [PreserveSig] int A6(); [PreserveSig] int A7(); [PreserveSig] int A8(); [PreserveSig] int A9();
        [PreserveSig] int A10(); [PreserveSig] int A11(); [PreserveSig] int A12(); [PreserveSig] int A13(); [PreserveSig] int A14();
        [PreserveSig] int A15(); [PreserveSig] int A16(); [PreserveSig] int A17(); [PreserveSig] int A18(); [PreserveSig] int A19();
        [PreserveSig] int A20(); [PreserveSig] int A21(); [PreserveSig] int A22(); [PreserveSig] int A23(); [PreserveSig] int A24();
        [PreserveSig] int A25(); [PreserveSig] int A26(); [PreserveSig] int A27(); [PreserveSig] int A28(); [PreserveSig] int A29();
        // IMFSample
        [PreserveSig] int GetSampleFlags(); [PreserveSig] int SetSampleFlags(); [PreserveSig] int GetSampleTime(); [PreserveSig] int SetSampleTime();
        [PreserveSig] int GetSampleDuration(); [PreserveSig] int SetSampleDuration(); [PreserveSig] int GetBufferCount(); [PreserveSig] int GetBufferByIndex();
        [PreserveSig] int ConvertToContiguousBuffer(out IMFMediaBuffer buffer);
        [PreserveSig] int AddBuffer(); [PreserveSig] int RemoveBufferByIndex(); [PreserveSig] int RemoveAllBuffers(); [PreserveSig] int GetTotalLength(); [PreserveSig] int CopyToBuffer();
    }
    [Guid("045FA593-8799-42b8-BC8D-8968C6453507"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMFMediaBuffer
    {
        [PreserveSig] int Lock(out IntPtr data, out int max, out int cur);
        [PreserveSig] int Unlock();
        [PreserveSig] int GetCurrentLength(out int len);
        [PreserveSig] int SetCurrentLength(int len);
        [PreserveSig] int GetMaxLength(out int len);
    }
    [Guid("70ae66f2-c809-4e4f-8915-bdcb406b7993"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMFSourceReader
    {
        [PreserveSig] int GetStreamSelection(int stream, out int selected);
        [PreserveSig] int SetStreamSelection(int stream, int selected);
        [PreserveSig] int GetNativeMediaType(int stream, int index, out IMFMediaType type);
        [PreserveSig] int GetCurrentMediaType(int stream, out IMFMediaType type);
        [PreserveSig] int SetCurrentMediaType(int stream, IntPtr reserved, IMFMediaType type);
        [PreserveSig] int SetCurrentPosition(ref Guid format, IntPtr pos);
        [PreserveSig] int ReadSample(int stream, int control, out int actual, out int flags, out long time, out IMFSample sample);
        [PreserveSig] int Flush(int stream);
        [PreserveSig] int GetServiceForStream(); [PreserveSig] int GetPresentationAttribute();
    }
    static class MF
    {
        [DllImport("mfplat.dll")] public static extern int MFStartup(int version, int flags);
        [DllImport("mfplat.dll")] public static extern int MFCreateMediaType(out IMFMediaType type);
        [DllImport("mfreadwrite.dll")] public static extern int MFCreateSourceReaderFromURL([MarshalAs(UnmanagedType.LPWStr)] string url, IntPtr attrs, out IMFSourceReader reader);
        public static Guid MajorType = new Guid("48eba18e-f8c9-4687-bf11-0a74c9f96a8f"), SubType = new Guid("f7e34c9a-42e8-4714-b74b-cb29d72c35e5");
        public static Guid Audio = new Guid("73647561-0000-0010-8000-00AA00389B71"), Float = new Guid("00000003-0000-0010-8000-00AA00389B71");
        public static Guid Channels = new Guid("37e48bf5-645e-4c5b-89de-ada9e29b696a"), Rate = new Guid("5faeeae7-0290-4c31-9e8a-c534f68d9dba");
        public const int FIRST_AUDIO = unchecked((int)0xFFFFFFFD), ALL = unchecked((int)0xFFFFFFFE);
        static bool started;
        public static void Start() { if (!started) { MFStartup(0x00020070, 0); started = true; } }
    }

    // a device's format (the shared mix format: float32 nearly always; 16/24-bit PCM handled too)
    // --- one program's own sound (Windows 10 2004+: process loopback) – Spotify through the helper's car-speaker chain,
    // EQ and all (2026-11-05) ---
    [ComImport, Guid("72A22D78-CDE4-431D-B8CC-843A71199B6D"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IActivateAudioInterfaceAsyncOperation
    {
        void GetActivateResult(out int hr, [MarshalAs(UnmanagedType.IUnknown)] out object iface);
    }
    [ComImport, Guid("41D949AB-9862-444A-80F6-C261334DA5EB"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IActivateAudioInterfaceCompletionHandler
    {
        void ActivateCompleted(IActivateAudioInterfaceAsyncOperation op);
    }
    [ComImport, Guid("94ea2b94-e9cc-49e0-c0ff-ee64ca8f5b90"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAgileObject { }
    [ComVisible(true), ClassInterface(ClassInterfaceType.None)]
    class ActivateHandler : IActivateAudioInterfaceCompletionHandler, IAgileObject
    {
        public readonly ManualResetEvent Done = new ManualResetEvent(false);
        public int Hr = -1; public object Client;
        public void ActivateCompleted(IActivateAudioInterfaceAsyncOperation op)
        {
            try { int hr; object o; op.GetActivateResult(out hr, out o); Hr = hr; Client = o; } catch (Exception) { Hr = -2; }
            Done.Set();
        }
    }
    static class ProcLoop
    {
        [DllImport("Mmdevapi.dll", ExactSpelling = true, PreserveSig = true)]
        static extern int ActivateAudioInterfaceAsync([MarshalAs(UnmanagedType.LPWStr)] string path, [MarshalAs(UnmanagedType.LPStruct)] Guid riid,
            IntPtr activationParams, IActivateAudioInterfaceCompletionHandler handler, out IActivateAudioInterfaceAsyncOperation op);
        static readonly Guid IID_AudioClient = new Guid("1CB9AD4C-DBFA-4c32-B178-C2F568A703B2");
        // the capture client of process `pid` (and its children), started, 48 kHz stereo float; null and why if not
        public static IAudioClient Open(int pid, out Fmt fmt, out string why)
        {
            fmt = null; why = null;
            IntPtr prm = Marshal.AllocHGlobal(12), pv = Marshal.AllocHGlobal(24), wf = Marshal.AllocHGlobal(18);
            try
            {
                Marshal.WriteInt32(prm, 0, 1);              // AUDIOCLIENT_ACTIVATION_TYPE_PROCESS_LOOPBACK
                Marshal.WriteInt32(prm, 4, pid);
                Marshal.WriteInt32(prm, 8, 0);              // PROCESS_LOOPBACK_MODE_INCLUDE_TARGET_PROCESS_TREE
                for (int i = 0; i < 24; i++) Marshal.WriteByte(pv, i, 0);
                Marshal.WriteInt16(pv, 0, 65);              // VT_BLOB
                Marshal.WriteInt32(pv, 8, 12);
                Marshal.WriteIntPtr(pv, 16, prm);
                var h = new ActivateHandler();
                IActivateAudioInterfaceAsyncOperation op;
                int hr = ActivateAudioInterfaceAsync("VAD\\Process_Loopback", IID_AudioClient, pv, h, out op);
                if (hr != 0) { why = "Aktivierung 0x" + hr.ToString("X8"); return null; }
                if (!h.Done.WaitOne(5000)) { why = "keine Antwort"; return null; }
                if (h.Hr != 0 || h.Client == null) { why = "Ergebnis 0x" + h.Hr.ToString("X8"); return null; }
                var c = (IAudioClient)h.Client;
                // WAVEFORMATEX: IEEE float, 2 ch, 48 kHz
                Marshal.WriteInt16(wf, 0, 3); Marshal.WriteInt16(wf, 2, 2); Marshal.WriteInt32(wf, 4, 48000);
                Marshal.WriteInt32(wf, 8, 48000 * 8); Marshal.WriteInt16(wf, 12, 8); Marshal.WriteInt16(wf, 14, 32); Marshal.WriteInt16(wf, 16, 0);
                hr = c.Initialize(0, 0x00020000 | unchecked((int)0x80000000) | 0x08000000, 2000000, 0, wf, IntPtr.Zero);
                if (hr != 0) { why = "Initialize 0x" + hr.ToString("X8"); return null; }
                fmt = new Fmt { Channels = 2, Rate = 48000, Bits = 32, Float = true };
                return c;
            }
            finally { Marshal.FreeHGlobal(prm); Marshal.FreeHGlobal(pv); Marshal.FreeHGlobal(wf); }
        }
    }

    // --- a program's own output device (Windows' "app volume and device preferences", as EarTrumpet sets it): Spotify
    // put on a device nobody hears (Steam Streaming Speakers), its sound taken from there through the helper's chain –
    // the mixer volume comes after any capture, so muting it there would silence the capture too (tested 2026-11-05) ---
    [ComImport, Guid("ab3d4648-e242-459f-b02f-541c70306324"), InterfaceType(ComInterfaceType.InterfaceIsIInspectable)]
    interface IAudioPolicyConfigFactory
    {
        int _0(); int _1(); int _2(); int _3(); int _4(); int _5(); int _6(); int _7(); int _8(); int _9();
        int _10(); int _11(); int _12(); int _13(); int _14(); int _15(); int _16(); int _17(); int _18();
        [PreserveSig] int SetPersistedDefaultAudioEndpoint(uint processId, int flow, int role, IntPtr deviceId);
        [PreserveSig] int GetPersistedDefaultAudioEndpoint(uint processId, int flow, int role, out IntPtr deviceId);
        [PreserveSig] int ClearAllPersistedApplicationDefaultEndpoints();
    }
    static class AppRoute
    {
        [DllImport("combase.dll", PreserveSig = false)] static extern void RoGetActivationFactory(IntPtr classId, ref Guid iid, [MarshalAs(UnmanagedType.IUnknown)] out object factory);
        [DllImport("combase.dll", PreserveSig = false)] static extern void WindowsCreateString([MarshalAs(UnmanagedType.LPWStr)] string s, int len, out IntPtr h);
        [DllImport("combase.dll", PreserveSig = false)] static extern void WindowsDeleteString(IntPtr h);
        [DllImport("combase.dll")] static extern IntPtr WindowsGetStringRawBuffer(IntPtr h, out uint len);
        const string RENDER = "#{e6327cad-dcec-4949-ae8a-991e976a79d2}", PREFIX = "\\\\?\\SWD#MMDEVAPI#";
        static IAudioPolicyConfigFactory f;
        static IAudioPolicyConfigFactory F()
        {
            if (f != null) return f;
            const string cls = "Windows.Media.Internal.AudioPolicyConfig";
            IntPtr h; WindowsCreateString(cls, cls.Length, out h);
            try { var g = new Guid("ab3d4648-e242-459f-b02f-541c70306324"); object o; RoGetActivationFactory(h, ref g, out o); f = (IAudioPolicyConfigFactory)o; }
            finally { WindowsDeleteString(h); }
            return f;
        }
        // the program's output (all roles) on device mmId (an IMMDevice id), or back to the default (null)
        public static bool Set(int pid, string mmId)
        {
            IntPtr h = IntPtr.Zero;
            if (mmId != null) { string full = PREFIX + mmId + RENDER; WindowsCreateString(full, full.Length, out h); }
            try
            {
                int a = F().SetPersistedDefaultAudioEndpoint((uint)pid, 0, 0, h);
                int b = F().SetPersistedDefaultAudioEndpoint((uint)pid, 0, 1, h);
                return a == 0 && b == 0;
            }
            finally { if (h != IntPtr.Zero) WindowsDeleteString(h); }
        }
        // the device the program is set to (its IMMDevice id), or null for the default
        public static string Get(int pid)
        {
            IntPtr h;
            if (F().GetPersistedDefaultAudioEndpoint((uint)pid, 0, 1, out h) != 0 || h == IntPtr.Zero) return null;
            try { uint n; var p = WindowsGetStringRawBuffer(h, out n); string s = Marshal.PtrToStringUni(p, (int)n); return s.Replace(PREFIX, "").Replace(RENDER, ""); }
            finally { WindowsDeleteString(h); }
        }
    }

    class Fmt
    {
        public int Channels, Rate, Bits; public bool Float;
        public static Fmt Read(IntPtr p)
        {
            var f = new Fmt();
            int tag = Marshal.ReadInt16(p, 0);
            f.Channels = Marshal.ReadInt16(p, 2);
            f.Rate = Marshal.ReadInt32(p, 4);
            f.Bits = Marshal.ReadInt16(p, 14);
            f.Float = tag == 3 || (tag == unchecked((short)0xFFFE) && f.Bits == 32 && Marshal.ReadInt32(p, 24) == 3);
            return f;
        }
    }

    // a two-pole filter (RBJ cookbook), one per channel
    class Biquad
    {
        double b0, b1, b2, a1, a2, x1, x2, y1, y2;
        public void Set(bool low, double fc, double rate)
        {
            double w = 2 * Math.PI * Math.Min(fc, rate * 0.45) / rate, c = Math.Cos(w), s = Math.Sin(w), q = 0.7071, al = s / (2 * q), a0 = 1 + al;
            if (low) { b0 = (1 - c) / 2; b1 = 1 - c; b2 = (1 - c) / 2; } else { b0 = (1 + c) / 2; b1 = -(1 + c); b2 = (1 + c) / 2; }
            a1 = -2 * c; a2 = 1 - al;
            b0 /= a0; b1 /= a0; b2 /= a0; a1 /= a0; a2 /= a0;
        }
        public double Run(double x)
        {
            double y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
            x2 = x1; x1 = x; y2 = y1; y1 = y;
            return y;
        }
    }

    // a peaking filter (RBJ): a resonance of the cab's body, the speakers' presence
    class Peak
    {
        double b0, b1, b2, a1, a2, x1, x2, y1, y2;
        public void Set(double fc, double q, double db, double rate)
        {
            double A = Math.Pow(10, db / 40), w = 2 * Math.PI * Math.Min(fc, rate * 0.45) / rate, al = Math.Sin(w) / (2 * q), c = Math.Cos(w), a0 = 1 + al / A;
            b0 = (1 + al * A) / a0; b1 = -2 * c / a0; b2 = (1 - al * A) / a0; a1 = -2 * c / a0; a2 = (1 - al / A) / a0;
        }
        public double Run(double x) { double y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2; x2 = x1; x1 = x; y2 = y1; y1 = y; return y; }
    }

    // a shelving filter (RBJ): the equalizer's bass and treble
    class Shelf
    {
        double b0, b1, b2, a1, a2, x1, x2, y1, y2;
        public void Set(bool low, double fc, double db, double rate)
        {
            double A = Math.Pow(10, db / 40), w = 2 * Math.PI * Math.Min(fc, rate * 0.45) / rate, c = Math.Cos(w), s = Math.Sin(w);
            double al = s / 2 * Math.Sqrt(2), sq = 2 * Math.Sqrt(A) * al, a0;
            if (low)
            {
                a0 = (A + 1) + (A - 1) * c + sq;
                b0 = A * ((A + 1) - (A - 1) * c + sq) / a0; b1 = 2 * A * ((A - 1) - (A + 1) * c) / a0; b2 = A * ((A + 1) - (A - 1) * c - sq) / a0;
                a1 = -2 * ((A - 1) + (A + 1) * c) / a0; a2 = ((A + 1) + (A - 1) * c - sq) / a0;
            }
            else
            {
                a0 = (A + 1) - (A - 1) * c + sq;
                b0 = A * ((A + 1) + (A - 1) * c + sq) / a0; b1 = -2 * A * ((A - 1) + (A + 1) * c) / a0; b2 = A * ((A + 1) + (A - 1) * c - sq) / a0;
                a1 = 2 * ((A - 1) - (A + 1) * c) / a0; a2 = ((A + 1) - (A - 1) * c - sq) / a0;
            }
        }
        public double Run(double x) { double y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2; x2 = x1; x1 = x; y2 = y1; y1 = y; return y; }
    }

    // a small room (Schroeder: four damped combs, two allpasses): the cab's walls heard from outside
    class Room
    {
        readonly double[][] comb; readonly int[] ci; readonly double[] cs; readonly double[][] ap; readonly int[] ai;
        public Room(int rate, int spread)
        {
            int[] cd = { 1116, 1188, 1277, 1356 }, ad = { 556, 441 };
            double k = rate / 44100.0 * 0.55;                      // (a small space: shorter than a hall)
            comb = new double[4][]; ci = new int[4]; cs = new double[4];
            for (int i = 0; i < 4; i++) comb[i] = new double[Math.Max(8, (int)((cd[i] + spread) * k))];
            ap = new double[2][]; ai = new int[2];
            for (int i = 0; i < 2; i++) ap[i] = new double[Math.Max(8, (int)((ad[i] + spread) * k))];
        }
        public double Run(double x)
        {
            double o = 0;
            for (int i = 0; i < 4; i++)
            {
                double y = comb[i][ci[i]];
                cs[i] = y * 0.62 + cs[i] * 0.38;                    // (damped: the walls swallow the treble)
                comb[i][ci[i]] = x + cs[i] * 0.72;
                ci[i] = (ci[i] + 1) % comb[i].Length;
                o += y;
            }
            o *= 0.25;
            for (int i = 0; i < 2; i++)
            {
                double b = ap[i][ai[i]];
                ap[i][ai[i]] = o + b * 0.5;
                o = b - o * 0.5;
                ai[i] = (ai[i] + 1) % ap[i].Length;
            }
            return o;
        }
    }

    // the whole sound of the radio for where the listener is: the speakers, the cab around them, the distance.
    // Targets per mode, approached smoothly (no clicks when the camera changes).
    class Fx
    {
        readonly int rate;
        readonly Biquad hpL = new Biquad(), hpR = new Biquad(), lpL = new Biquad(), lpR = new Biquad(), lp2L = new Biquad(), lp2R = new Biquad();
        readonly Peak pkL = new Peak(), pkR = new Peak(), prL = new Peak(), prR = new Peak();
        readonly Room roomL, roomR;
        readonly double[] dlL = new double[512], dlR = new double[512]; int dw; double lfo;
        // current / target
        public double Gain, GainT, Low = 20000, LowT = 20000, High = 20, HighT = 20, Boom, BoomT, Pres, PresT, Drive = 1, DriveT = 1, Wet, WetT, Wow, WowT;
        double setLow = -1, setHigh = -1, setBoom = -99, setPres = -99;
        public Fx(int rate) { this.rate = rate; roomL = new Room(rate, 0); roomR = new Room(rate, 23); }

        // the equalizer (the radio app's three knobs, dB −12..+12): bass 110 Hz shelf, mid 1 kHz, treble 5 kHz shelf
        readonly Shelf eqBL = new Shelf(), eqBR = new Shelf(), eqTL = new Shelf(), eqTR = new Shelf();
        readonly Peak eqML = new Peak(), eqMR = new Peak();
        public double EqB, EqM, EqT; double setB = -99, setM = -99, setT = -99;
        public void Eq(double b, double m, double t) { EqB = Math.Max(-12, Math.Min(12, b)); EqM = Math.Max(-12, Math.Min(12, m)); EqT = Math.Max(-12, Math.Min(12, t)); }
        void EqSet()
        {
            if (Math.Abs(EqB - setB) > 0.05) { eqBL.Set(true, 110, EqB, rate); eqBR.Set(true, 110, EqB, rate); setB = EqB; }
            if (Math.Abs(EqM - setM) > 0.05) { eqML.Set(1000, 0.7, EqM, rate); eqMR.Set(1000, 0.7, EqM, rate); setM = EqM; }
            if (Math.Abs(EqT - setT) > 0.05) { eqTL.Set(false, 5000, EqT, rate); eqTR.Set(false, 5000, EqT, rate); setT = EqT; }
        }

        public void Target(string mode, double vol, double dist, bool duck, bool passthrough)
        {
            switch (mode)
            {
                case "cab":      // the truck's speakers from the driver's seat: a little bass and treble cut, a touch of presence, the cab's air
                    GainT = vol; LowT = 12500; HighT = 75; BoomT = 1.5; PresT = 1.5; DriveT = 1.0; WetT = 0.05; WowT = 0; break;
                case "outside":  // the cab closed, heard from outside: dull, the body booming a bit, the speakers working
                    GainT = vol * 0.42; LowT = 1500; HighT = 65; BoomT = 5; PresT = 0; DriveT = 1.7; WetT = 0.2; WowT = 0.12; break;
                case "walk":     // on foot: duller and roomier with the distance, fading out over ~45 m
                    double f = Math.Max(0, 1 - dist / 45);
                    GainT = vol * 0.5 * f * f * (3 - 2 * f) + 0.0;
                    LowT = Math.Max(420, 1500 - dist * 26); HighT = 65; BoomT = 5; PresT = 0; DriveT = 1.7;
                    WetT = Math.Min(0.4, 0.2 + dist * 0.005); WowT = 0.18; break;
                case "off": GainT = 0; goto default;
                default:
                    if (mode != "off") GainT = passthrough ? 1 : 0;
                    LowT = 20000; HighT = 20; BoomT = 0; PresT = 0; DriveT = 1; WetT = 0; WowT = 0; break;
            }
            if (duck) GainT *= 0.3;
        }

        // per output block: the filters follow their targets
        public void Block()
        {
            Low += (LowT - Low) * 0.15; High += (HighT - High) * 0.15; Boom += (BoomT - Boom) * 0.15; Pres += (PresT - Pres) * 0.15;
            Drive += (DriveT - Drive) * 0.1; Wet += (WetT - Wet) * 0.1; Wow += (WowT - Wow) * 0.1;
            if (Math.Abs(Low - setLow) > 5) { lpL.Set(true, Low, rate); lpR.Set(true, Low, rate); bool two = Low < 6000; lp2L.Set(true, two ? Low * 1.6 : 22000, rate); lp2R.Set(true, two ? Low * 1.6 : 22000, rate); setLow = Low; }
            if (Math.Abs(High - setHigh) > 1) { hpL.Set(false, High, rate); hpR.Set(false, High, rate); setHigh = High; }
            if (Math.Abs(Boom - setBoom) > 0.05) { pkL.Set(170, 1.1, Boom, rate); pkR.Set(170, 1.1, Boom, rate); setBoom = Boom; }
            if (Math.Abs(Pres - setPres) > 0.05) { prL.Set(2600, 0.9, Pres, rate); prR.Set(2600, 0.9, Pres, rate); setPres = Pres; }
            EqSet();
        }

        public void Run(ref float l, ref float r)
        {
            Gain += (GainT - Gain) * 0.0008;
            double L = l, R = r;
            // a speaker a little loose: its cone wobbles – a slow, tiny pitch waver (a short delay swaying)
            if (Wow > 0.005)
            {
                dlL[dw] = L; dlR[dw] = R;
                lfo += 2 * Math.PI * 0.55 / rate; if (lfo > 2 * Math.PI) lfo -= 2 * Math.PI;
                double d = (0.35 + Wow * (1 + Math.Sin(lfo) + 0.3 * Math.Sin(lfo * 3.7))) * rate / 1000.0;     // ms → samples
                double rp = dw - d; while (rp < 0) rp += dlL.Length;
                int i0 = (int)rp, i1 = (i0 + 1) % dlL.Length; double fr = rp - i0;
                L = dlL[i0] + (dlL[i1] - dlL[i0]) * fr; R = dlR[i0] + (dlR[i1] - dlR[i0]) * fr;
            }
            dw = (dw + 1) % dlL.Length;
            // the radio's own sound first (the knobs), then the way to the listener
            if (Math.Abs(EqB) > 0.05) { L = eqBL.Run(L); R = eqBR.Run(R); }
            if (Math.Abs(EqM) > 0.05) { L = eqML.Run(L); R = eqMR.Run(R); }
            if (Math.Abs(EqT) > 0.05) { L = eqTL.Run(L); R = eqTR.Run(R); }
            L = lp2L.Run(lpL.Run(hpL.Run(L))); R = lp2R.Run(lpR.Run(hpR.Run(R)));
            if (Math.Abs(Boom) > 0.05) { L = pkL.Run(L); R = pkR.Run(R); }
            if (Math.Abs(Pres) > 0.05) { L = prL.Run(L); R = prR.Run(R); }
            // the speakers pushed: a soft saturation (the level kept about the same)
            if (Drive > 1.02) { double k = 1 / Math.Tanh(Drive * 0.6); L = Math.Tanh(L * Drive * 0.6) * k / Drive * 1.25; R = Math.Tanh(R * Drive * 0.6) * k / Drive * 1.25; }
            // the room
            if (Wet > 0.005) { double m = (L + R) * 0.5; double wl = roomL.Run(m), wr = roomR.Run(m); L = L * (1 - Wet * 0.5) + wl * Wet * 1.6; R = R * (1 - Wet * 0.5) + wr * Wet * 1.6; }
            // (a boost on the knobs takes headroom: half of the largest boost back, then a soft limit above 0.85)
            double comp = Math.Pow(10, -Math.Max(0, Math.Max(EqB, Math.Max(EqM, EqT))) * 0.5 / 20);
            L *= Gain * comp; R *= Gain * comp;
            if (Math.Abs(L) > 0.85) L = Math.Sign(L) * (0.85 + 0.15 * Math.Tanh((Math.Abs(L) - 0.85) / 0.15));
            if (Math.Abs(R) > 0.85) R = Math.Sign(R) * (0.85 + 0.15 * Math.Tanh((Math.Abs(R) - 0.85) / 0.15));
            l = (float)L; r = (float)R;
        }
    }

    // stereo frames waiting to be played (filled by the capture or the decoder, emptied by the speakers)
    class Ring
    {
        readonly float[] L, R; readonly int N; int wr, rd, have; readonly object K = new object();
        public Ring(int n) { N = n; L = new float[n]; R = new float[n]; }
        public void Push(float l, float r) { lock (K) { if (have < N) { L[wr] = l; R[wr] = r; wr = (wr + 1) % N; have++; } } }
        public bool Pop(out float l, out float r)
        {
            lock (K) { if (have > 0) { l = L[rd]; r = R[rd]; rd = (rd + 1) % N; have--; return true; } }
            l = r = 0; return false;
        }
        public void Trim(int max) { lock (K) { if (have > max) { int d = have - max; rd = (rd + d) % N; have -= d; } } }
        public int Have { get { lock (K) return have; } }
        public void Clear() { lock (K) { wr = rd = have = 0; } }
    }
    // linear resampling into the ring at the speakers' rate
    class Resampler
    {
        readonly double step; double pos; float pl, pr; readonly Ring ring;
        public Resampler(int from, int to, Ring r) { step = (double)from / to; ring = r; }
        public void Push(float l, float r)
        {
            while (pos < 1) { ring.Push(pl + (l - pl) * (float)pos, pr + (r - pr) * (float)pos); pos += step; }
            pos -= 1; pl = l; pr = r;
        }
    }

    class Engine
    {
        const int CLSCTX_ALL = 23, SHARED = 0, LOOPBACK = 0x00020000, eRender = 0, eConsole = 0;
        static Guid IID_AudioClient = new Guid("1CB9AD4C-DBFA-4c32-B178-C2F568A703B2");
        static Guid IID_Capture = new Guid("C8ADBD64-E71E-48a0-A4DE-185C395CD317");
        static Guid IID_Render = new Guid("F294ACFC-3146-4483-A7BF-ADDCA7C260E2");
        static Guid IID_Sessions = new Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F");
        static PropertyKey FriendlyName = new PropertyKey { fmtid = new Guid("a45c254e-df1c-4efd-8020-67d146a850e0"), pid = 14 };
        // (the music programs whose mixer volume is set in the "spotify" source)
        static readonly string[] Players = { "spotify", "deezer", "amazon music", "tidal", "applemusic", "music.ui", "wmplayer", "vlc", "foobar2000", "musicbee", "aimp", "itunes" };

        public string SourceName = "Steam Streaming Speakers";
        public string Status = "startet …", Title = "";
        public volatile bool Stop;
        public string StateFile, HeartbeatFile;
        public double Level; public bool Ok;

        // what the game wants
        public volatile string Src = "idle", Url = "";
        string mode = "normal"; int seq = -1;
        double stVol = 0.7, stDist = 0, stB, stM, stT; bool stDuck;
        // the shaping, smoothed towards its target
        double gain = 0, gainT = 0, lowFc = 20000, lowT = 20000, highFc = 20, highT = 20;
        DateTime stateRead = DateTime.MinValue, beat = DateTime.MinValue, staleSince = DateTime.MinValue;

        static string NameOf(IMMDevice d)
        {
            IPropertyStore ps; if (d.OpenPropertyStore(0, out ps) != 0) return "";
            PropVariant v; var k = FriendlyName; ps.GetValue(ref k, out v);
            return v.p != IntPtr.Zero ? Marshal.PtrToStringUni(v.p) : "";
        }
        static List<IMMDevice> Renders(IMMDeviceEnumerator en)
        {
            var l = new List<IMMDevice>();
            IMMDeviceCollection col; en.EnumAudioEndpoints(eRender, 1, out col);
            int n; col.GetCount(out n);
            for (int i = 0; i < n; i++) { IMMDevice d; col.Item(i, out d); l.Add(d); }
            return l;
        }
        static IMMDevice FindRender(IMMDeviceEnumerator en, string name)
        {
            foreach (var d in Renders(en)) if (NameOf(d).IndexOf(name, StringComparison.OrdinalIgnoreCase) >= 0) return d;
            return null;
        }
        static string Str(string j, string key)
        {
            var m = Regex.Match(j, "\"" + key + "\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"");
            return m.Success ? m.Groups[1].Value.Replace("\\/", "/").Replace("\\\"", "\"") : null;
        }
        static double Num(string j, string key, double def)
        {
            var m = Regex.Match(j, "\"" + key + "\"\\s*:\\s*\"?([0-9.eE+-]+)"); double v;   // (also "123.4": a livestream's clock is written as text, all its digits kept)
            return m.Success && double.TryParse(m.Groups[1].Value, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out v) ? v : def;
        }

        // --- the media keys (they go to whichever player has the media session: Spotify) ---
        [DllImport("user32.dll")] static extern void keybd_event(byte vk, byte scan, int flags, IntPtr extra);
        static void MediaKey(byte vk) { keybd_event(vk, 0, 1, IntPtr.Zero); keybd_event(vk, 0, 3, IntPtr.Zero); }

        // the game's state → the source and the target shaping
        public void ReadState()
        {
            if ((DateTime.Now - stateRead).TotalMilliseconds < 120) return;
            stateRead = DateTime.Now;
            double dist = 0, vol = 0.7; bool duck = false; string src = null, url = null, cmd = null; int sq = seq;
            mode = "normal";
            try
            {
                var fi = new FileInfo(StateFile);
                // (no word from the game for 4 s: it is closed or loading)
                if (fi.Exists && (DateTime.Now - fi.LastWriteTime).TotalSeconds < 4)
                {
                    // (read sharing the file: File.ReadAllText locked the game's writer out now and then –
                    // "Unable to open file for writing: radio_state.json" in beamng.log, 2026-11-06)
                    string j;
                    using (var fs = new FileStream(StateFile, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
                    using (var sr = new StreamReader(fs, System.Text.Encoding.UTF8)) j = sr.ReadToEnd();
                    mode = Str(j, "mode") ?? "normal";
                    dist = Num(j, "dist", 0); vol = Num(j, "vol", 0.7);
                    duck = Regex.IsMatch(j, "\"duck\"\\s*:\\s*true");
                    src = Str(j, "src"); url = Str(j, "url"); cmd = Str(j, "cmd"); sq = (int)Num(j, "seq", seq);
                    // the video player's sound: where the picture is (s) and whether it runs
                    double vp = Num(j, "vpos", -1);
                    if (vp >= 0 && Math.Abs(vp - VPos) > 0.01) { VPos = vp; VPosAt = DateTime.Now; }
                    VPlay = Regex.IsMatch(j, "\"vplay\"\\s*:\\s*true");
                    stB = Num(j, "eqB", 0); stM = Num(j, "eqM", 0); stT = Num(j, "eqT", 0);
                }
            }
            catch { }
            if (mode == "normal")
            {
                // (the game away: after a little while the stream stops and the player's volume goes back)
                if (staleSince == DateTime.MinValue) staleSince = DateTime.Now;
                if ((DateTime.Now - staleSince).TotalSeconds > 6) Src = Src == "line" ? "line" : "idle";
            }
            else
            {
                staleSince = DateTime.MinValue;
                string want = src == "spotify" || src == "line" || src == "video" ? src : "radio";
                if (mode == "off" && (want == "radio" || want == "video")) want = "idle";
                if ((want == "radio" || want == "video") && string.IsNullOrEmpty(url)) want = "idle";
                Src = want;
                if (want == "radio" || want == "video") Url = url;
                // a button in the cab app: the media key, once per press
                if (sq != seq) { if (seq >= 0 && !string.IsNullOrEmpty(cmd)) { if (cmd == "play") MediaKey(0xB3); else if (cmd == "next") MediaKey(0xB0); else if (cmd == "prev") MediaKey(0xB1); } seq = sq; }
            }
            switch (mode)
            {
                case "cab": gainT = vol; lowT = 11000; highT = 90; break;
                case "outside": gainT = vol * 0.4; lowT = 750; highT = 60; break;
                case "walk": gainT = vol * 0.45 * Math.Max(0, 1 - dist / 45); lowT = Math.Max(300, 900 - dist * 12); highT = 60; break;
                case "off": gainT = 0; lowT = 20000; highT = 20; break;
                default: gainT = Src == "line" ? 1 : 0; lowT = 20000; highT = 20; break;
            }
            // (Spotify cannot be muffled from here, only turned down: much further than the filtered radio – it was too loud
            // on getting out and walking off)
            if (Src == "spotify")
            {
                if (mode == "outside") gainT = vol * 0.18;
                else if (mode == "walk") gainT = vol * 0.2 * Math.Pow(Math.Max(0, 1 - dist / 32), 1.6);
            }
            if (duck) gainT *= 0.3;
            stVol = vol; stDist = dist; stDuck = duck;
            if ((DateTime.Now - beat).TotalSeconds > 1.0) { beat = DateTime.Now; Beat(); }
        }

        static string Esc(string s) { return (s ?? "").Replace("\\", "/").Replace("\"", "'").Replace("\r", " ").Replace("\n", " "); }
        public void Beat()
        {
            try
            {
                File.WriteAllText(HeartbeatFile, "{\"t\":" + (long)(DateTime.UtcNow - new DateTime(1970, 1, 1)).TotalSeconds +
                    ",\"status\":\"" + Esc(Status) + "\",\"src\":\"" + Esc(Src) + "\",\"title\":\"" + Esc(Title) + "\",\"ok\":" + (Ok ? "true" : "false") +
                    ",\"video\":\"" + Esc(VideoFile) + "\",\"videoFor\":\"" + Esc(VideoFor) + "\",\"live\":\"" + Esc(LiveUrl) + "\",\"liveFor\":\"" + Esc(LiveFor) + "\",\"videoMB\":" + VideoMB.ToString("0.0", System.Globalization.CultureInfo.InvariantCulture) +
                    ",\"level\":" + Level.ToString("0.000", System.Globalization.CultureInfo.InvariantCulture) + "}");
            }
            catch { }
        }

        // --- the player programs in the Windows mixer ---
        readonly Dictionary<int, float> original = new Dictionary<int, float>();   // pid -> its volume before the game touched it
        List<KeyValuePair<int, ISimpleAudioVolume>> sessions = new List<KeyValuePair<int, ISimpleAudioVolume>>();
        DateTime sessionsAt = DateTime.MinValue; float lastSet = -1;

        static string ProcName(int pid) { try { return Process.GetProcessById(pid).ProcessName; } catch { return ""; } }
        static bool IsPlayer(string name) { name = name.ToLowerInvariant(); foreach (var p in Players) if (name == p || name.StartsWith(p)) return true; return false; }

        List<KeyValuePair<int, ISimpleAudioVolume>> FindSessions(bool all)
        {
            var res = new List<KeyValuePair<int, ISimpleAudioVolume>>();
            var en = (IMMDeviceEnumerator)new MMDeviceEnumeratorCo();
            foreach (var d in Renders(en))
            {
                object o; if (d.Activate(ref IID_Sessions, CLSCTX_ALL, IntPtr.Zero, out o) != 0) continue;
                var mgr = (IAudioSessionManager2)o;
                IAudioSessionEnumerator se; if (mgr.GetSessionEnumerator(out se) != 0) continue;
                int n; se.GetCount(out n);
                for (int i = 0; i < n; i++)
                {
                    object s; if (se.GetSession(i, out s) != 0 || s == null) continue;
                    var c2 = s as IAudioSessionControl2; var sv = s as ISimpleAudioVolume;
                    int pid; if (c2 == null || sv == null || c2.GetProcessId(out pid) != 0 || pid == 0) continue;
                    if (all || IsPlayer(ProcName(pid))) res.Add(new KeyValuePair<int, ISimpleAudioVolume>(pid, sv));
                }
            }
            return res;
        }
        // a test: 3 s of process `pid`'s sound with its mixer volume at `vol` (0 = silent in the mixer) – the level heard
        public static void PlbTest(int pid, float vol)
        {
            var e = new Engine();
            ISimpleAudioVolume sv = null; float orig = 1;
            foreach (var kv in e.FindSessions(true)) if (kv.Key == pid) { sv = kv.Value; sv.GetMasterVolume(out orig); }
            if (sv != null) sv.SetMasterVolume(vol, IntPtr.Zero);
            try
            {
                Fmt f; string why;
                var c = ProcLoop.Open(pid, out f, out why);
                if (c == null) { Console.WriteLine("FAIL " + why); return; }
                object o; c.GetService(ref IID_Capture, out o); var cap = (IAudioCaptureClient)o;
                c.Start();
                double sum = 0; long n = 0; var t0 = DateTime.Now;
                while ((DateTime.Now - t0).TotalSeconds < 3)
                {
                    int pkt; cap.GetNextPacketSize(out pkt);
                    while (pkt > 0)
                    {
                        IntPtr d; int fr, fl; long a, b;
                        if (cap.GetBuffer(out d, out fr, out fl, out a, out b) != 0) break;
                        for (int i = 0; i < fr; i++) { float s = (fl & 2) != 0 ? 0 : Sample(d, i * 2, f); sum += s * s; n++; }
                        cap.ReleaseBuffer(fr); cap.GetNextPacketSize(out pkt);
                    }
                    Thread.Sleep(10);
                }
                c.Stop();
                Console.WriteLine("OK frames " + n + " rms " + (n > 0 ? Math.Sqrt(sum / n) : 0).ToString("0.00000") + " (mixer vol " + vol + ")");
            }
            finally { if (sv != null) sv.SetMasterVolume(orig, IntPtr.Zero); }
        }
        // a test: process `pid` put on "Steam Streaming Speakers", read back, put back
        public static void RouteTest(int pid)
        {
            var en = (IMMDeviceEnumerator)new MMDeviceEnumeratorCo();
            var dev = FindRender(en, "Steam Streaming Speakers");
            if (dev == null) { Console.WriteLine("no Steam Streaming Speakers"); return; }
            string id; dev.GetId(out id);
            Console.WriteLine("before: " + (AppRoute.Get(pid) ?? "(default)"));
            Console.WriteLine("set: " + AppRoute.Set(pid, id));
            Console.WriteLine("now: " + (AppRoute.Get(pid) ?? "(default)"));
            Console.WriteLine("reset: " + AppRoute.Set(pid, null));
            Console.WriteLine("after: " + (AppRoute.Get(pid) ?? "(default)"));
        }
        public static void ListSessions()
        {
            var e = new Engine();
            foreach (var kv in e.FindSessions(true)) { float v; kv.Value.GetMasterVolume(out v); Console.WriteLine(kv.Key + "  " + ProcName(kv.Key) + "  vol " + v.ToString("0.00") + (IsPlayer(ProcName(kv.Key)) ? "  <- Player" : "")); }
        }
        void SetPlayers(float v)
        {
            if ((DateTime.Now - sessionsAt).TotalSeconds > 3) { sessionsAt = DateTime.Now; try { sessions = FindSessions(false); } catch { sessions = new List<KeyValuePair<int, ISimpleAudioVolume>>(); } lastSet = -1; }
            if (Math.Abs(v - lastSet) < 0.005) return;
            lastSet = v;
            foreach (var kv in sessions)
            {
                try
                {
                    if (!original.ContainsKey(kv.Key)) { float o; kv.Value.GetMasterVolume(out o); original[kv.Key] = o; }
                    kv.Value.SetMasterVolume(Math.Max(0, Math.Min(1, v)), IntPtr.Zero);
                }
                catch { }
            }
            Ok = sessions.Count > 0;
        }
        public void RestorePlayers()
        {
            if (original.Count == 0) return;
            try
            {
                foreach (var kv in FindSessions(false)) { float o; if (original.TryGetValue(kv.Key, out o)) kv.Value.SetMasterVolume(o, IntPtr.Zero); }
            }
            catch { }
            original.Clear(); lastSet = -1;
        }
        static string SpotifyTitle()
        {
            try
            {
                foreach (var p in Process.GetProcessesByName("Spotify"))
                {
                    string t = p.MainWindowTitle;
                    if (!string.IsNullOrEmpty(t)) return t.StartsWith("Spotify") ? "" : t;     // ("Spotify Premium": paused)
                }
            }
            catch { }
            return null;
        }

        // --- the sample formats ---
        static float Sample(IntPtr p, int i, Fmt f)
        {
            if (f.Float) return BitConverter.ToSingle(BitConverter.GetBytes(Marshal.ReadInt32(p, i * 4)), 0);
            if (f.Bits == 16) return Marshal.ReadInt16(p, i * 2) / 32768f;
            if (f.Bits == 24) { int b = Marshal.ReadByte(p, i * 3) | (Marshal.ReadByte(p, i * 3 + 1) << 8) | ((sbyte)Marshal.ReadByte(p, i * 3 + 2) << 16); return b / 8388608f; }
            return Marshal.ReadInt32(p, i * 4) / 2147483648f;
        }
        static void Put(IntPtr p, int i, Fmt f, float v)
        {
            v = Math.Max(-1f, Math.Min(1f, v));
            if (f.Float) Marshal.WriteInt32(p, i * 4, BitConverter.ToInt32(BitConverter.GetBytes(v), 0));
            else if (f.Bits == 16) Marshal.WriteInt16(p, i * 2, (short)(v * 32767));
            else if (f.Bits == 24) { int b = (int)(v * 8388607); Marshal.WriteByte(p, i * 3, (byte)b); Marshal.WriteByte(p, i * 3 + 1, (byte)(b >> 8)); Marshal.WriteByte(p, i * 3 + 2, (byte)(b >> 16)); }
            else Marshal.WriteInt32(p, i * 4, (int)(v * 2147483647));
        }

        // --- an internet station: decoded on its own thread into the ring (a stalled stream never blocks the sound) ---
        int gen;
        public static IMFSourceReader OpenStream(string url, out int rate, out int ch)
        {
            MF.Start();
            IMFSourceReader rd;
            int hr = MF.MFCreateSourceReaderFromURL(url, IntPtr.Zero, out rd);
            if (hr != 0 || rd == null) throw new Exception("Sender nicht erreichbar (0x" + hr.ToString("X8") + ")");
            rd.SetStreamSelection(MF.ALL, 0); rd.SetStreamSelection(MF.FIRST_AUDIO, 1);
            IMFMediaType t; MF.MFCreateMediaType(out t);
            var k1 = MF.MajorType; var v1 = MF.Audio; t.SetGUID(ref k1, ref v1);
            var k2 = MF.SubType; var v2 = MF.Float; t.SetGUID(ref k2, ref v2);
            hr = rd.SetCurrentMediaType(MF.FIRST_AUDIO, IntPtr.Zero, t);
            if (hr != 0) throw new Exception("Format nicht lesbar (0x" + hr.ToString("X8") + ")");
            IMFMediaType ct; rd.GetCurrentMediaType(MF.FIRST_AUDIO, out ct);
            var kr = MF.Rate; var kc = MF.Channels;
            ct.GetUINT32(ref kr, out rate); ct.GetUINT32(ref kc, out ch);
            if (ch < 1) ch = 2; if (rate < 8000) rate = 44100;
            return rd;
        }
        // one decoded block: frames of float PCM handed to `put`; false at the end of the stream
        public static bool ReadBlock(IMFSourceReader rd, int ch, Action<float, float> put)
        {
            int idx, flags; long ts; IMFSample s;
            int hr = rd.ReadSample(MF.FIRST_AUDIO, 0, out idx, out flags, out ts, out s);
            if (hr != 0 || (flags & 3) != 0) return false;
            if (s == null) return true;
            IMFMediaBuffer b;
            if (s.ConvertToContiguousBuffer(out b) == 0 && b != null)
            {
                IntPtr p; int max, cur;
                if (b.Lock(out p, out max, out cur) == 0)
                {
                    var tmp = new float[cur / 4]; Marshal.Copy(p, tmp, 0, tmp.Length); b.Unlock();
                    for (int i = 0; i + ch - 1 < tmp.Length; i += ch) put(tmp[i], ch > 1 ? tmp[i + 1] : tmp[i]);
                }
                Marshal.ReleaseComObject(b);
            }
            Marshal.ReleaseComObject(s);
            return true;
        }
        // --- the video player's sound (2026-11-04): the game's video window plays muted and tells where it is (vpos,
        // vplay); the sound comes from here, through the same car-speaker sound. A direct link (.mp4, .webm, .m4a…) is
        // decoded as it is; a YouTube link first goes through yt-dlp (fetched once from its GitHub releases next to this
        // program) for the address of its audio. Kept in step: more than 1.5 s apart → a jump to where the picture is.
        public volatile bool VPlay; public double VPos; public DateTime VPosAt = DateTime.Now;
        static readonly System.Collections.Generic.Dictionary<string, string> audioOf = new System.Collections.Generic.Dictionary<string, string>();
        static string YtId(string u)
        {
            var m = Regex.Match(u ?? "", @"(?:youtu\.be/|youtube\.com/(?:watch\?(?:.*&)?v=|shorts/|embed/|live/))([\w-]{11})");
            if (m.Success) return m.Groups[1].Value;
            return Regex.IsMatch(u ?? "", @"^[\w-]{11}$") ? u : null;
        }
        string ResolveAudio(string url)
        {
            string id = YtId(url);
            if (id == null) return url;                               // (a direct link)
            string cached; if (audioOf.TryGetValue(id, out cached)) return cached;
            string dir = Path.GetDirectoryName(Application.ExecutablePath);
            string exe = Path.Combine(dir, "yt-dlp.exe");
            if (!File.Exists(exe))
            {
                Status = "lade yt-dlp (einmalig, ~18 MB) …";
                System.Net.ServicePointManager.SecurityProtocol = (System.Net.SecurityProtocolType)3072;    // (TLS 1.2)
                using (var wc = new System.Net.WebClient())
                    wc.DownloadFile("https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe", exe + ".part");
                File.Move(exe + ".part", exe);
            }
            // (the sound downloaded once into the cache – a few MB, some seconds; streaming from YouTube's servers needs
            // their headers and was refused)
            string cache = CacheDir();
            foreach (var f in Directory.GetFiles(cache, id + ".*")) if (!f.EndsWith(".part")) { audioOf[id] = f; return f; }
            Status = "YouTube-Ton wird geladen …";
            var psi = new ProcessStartInfo(exe, "-f \"140/bestaudio[ext=m4a]/bestaudio\" --no-playlist --no-warnings --no-progress -o \""
                + Path.Combine(cache, id + ".%(ext)s") + "\" \"https://www.youtube.com/watch?v=" + id + "\"")
            { UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true, CreateNoWindow = true };
            using (var p = Process.Start(psi))
            {
                p.StandardOutput.ReadToEnd();
                string err = p.StandardError.ReadToEnd();
                p.WaitForExit(120000);
                foreach (var f in Directory.GetFiles(cache, id + ".*")) if (!f.EndsWith(".part")) { audioOf[id] = f; Prune(cache); return f; }
                throw new Exception("yt-dlp: " + (err ?? "").Split('\n')[0].Trim());
            }
        }
        static string CacheDir()
        {
            string d = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "BeamNG", "BeamNG.drive", "current", "temp", "fernfahrer", "videoaudio");
            Directory.CreateDirectory(d);
            return d;
        }
        // (the cache kept small: the newest 12)
        static void Prune(string dir)
        {
            var files = new DirectoryInfo(dir).GetFiles();
            Array.Sort(files, (a, b) => b.LastWriteTime.CompareTo(a.LastWriteTime));
            for (int i = 12; i < files.Length; i++) { try { files[i].Delete(); } catch { } }
        }
        // a direct link the decoder may not open itself (the server refuses it): downloaded into the cache first
        string Download(string url)
        {
            string name = "dl_" + ((uint)url.GetHashCode()).ToString("x8") + Path.GetExtension(new Uri(url).AbsolutePath);
            string file = Path.Combine(CacheDir(), name);
            if (File.Exists(file)) return file;
            Status = "Video-Ton wird geladen …";
            System.Net.ServicePointManager.SecurityProtocol = (System.Net.SecurityProtocolType)3072;
            using (var wc = new System.Net.WebClient())
            {
                wc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Fernfahrer-Radio");
                wc.DownloadFile(url, file + ".part");
            }
            File.Move(file + ".part", file);
            Prune(CacheDir());
            return file;
        }
        static void Seek(IMFSourceReader rd, double sec)
        {
            IntPtr pv = Marshal.AllocHGlobal(24);
            try
            {
                for (int i = 0; i < 24; i++) Marshal.WriteByte(pv, i, 0);
                Marshal.WriteInt16(pv, 0, 20);                         // (VT_I8: 100-ns units)
                Marshal.WriteInt64(pv, 8, (long)(Math.Max(0, sec) * 1e7));
                var g = Guid.Empty;
                rd.SetCurrentPosition(ref g, pv);
            }
            finally { Marshal.FreeHGlobal(pv); }
        }
        static bool ReadBlockTs(IMFSourceReader rd, int ch, Action<float, float> put, out double tsSec, out int frames)
        {
            int idx, flags; long ts; IMFSample s; tsSec = -1; frames = 0;
            int hr = rd.ReadSample(MF.FIRST_AUDIO, 0, out idx, out flags, out ts, out s);
            if (hr != 0 || (flags & 3) != 0) return false;
            if (s == null) return true;
            tsSec = ts / 1e7;
            IMFMediaBuffer b;
            if (s.ConvertToContiguousBuffer(out b) == 0 && b != null)
            {
                IntPtr p; int max, cur;
                if (b.Lock(out p, out max, out cur) == 0)
                {
                    var tmp = new float[cur / 4]; Marshal.Copy(p, tmp, 0, tmp.Length); b.Unlock();
                    for (int i = 0; i + ch - 1 < tmp.Length; i += ch) { put(tmp[i], ch > 1 ? tmp[i + 1] : tmp[i]); frames++; }
                }
                Marshal.ReleaseComObject(b);
            }
            Marshal.ReleaseComObject(s);
            return true;
        }
        // the picture of a YouTube video (2026-11-04): YouTube's embedded player refuses pages without a web address
        // ("Error 153" – the game's UI runs under local://). So the video itself is fetched too (480p, no sound – the
        // sound is the audio file above) into the game's temp folder; the game's player and the truck's screen show that
        // file (local://local/temp/...). VideoFile: its path under the game's user folder once ready; VideoMB: so far.
        public volatile string VideoFile = "", VideoFor = "";
        public double VideoMB;
        int videoGen;
        void FetchVideo(string url)
        {
            string id = YtId(url);
            if (id == null) { VideoFile = ""; VideoFor = url; return; }
            if (VideoFor == url && (VideoFile != "" || VideoMB > 0)) return;     // (done, or on its way)
            VideoFor = url; VideoFile = ""; VideoMB = 0.001;
            int my = ++videoGen;
            var th = new Thread(() =>
            {
                try
                {
                    string cache = CacheDir();
                    Func<string> done = () =>
                    {
                        foreach (var f in Directory.GetFiles(cache, id + ".v.*"))
                            if (!f.EndsWith(".part") && !f.Contains(".part-") && !f.EndsWith(".ytdl")) return f;
                        return null;
                    };
                    string file = done();
                    if (file == null)
                    {
                        string exe = Path.Combine(Path.GetDirectoryName(Application.ExecutablePath), "yt-dlp.exe");
                        int waited = 0;
                        while (!File.Exists(exe) && waited++ < 120) Thread.Sleep(500);        // (the audio's fetch brings it)
                        var psi = new ProcessStartInfo(exe, "-f \"bestvideo[height<=480][ext=webm]/bestvideo[height<=480]/18\" --no-playlist --no-warnings --no-progress -o \""
                            + Path.Combine(cache, id + ".v.%(ext)s") + "\" \"https://www.youtube.com/watch?v=" + id + "\"")
                        { UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true, CreateNoWindow = true };
                        using (var p = Process.Start(psi))
                        {
                            p.OutputDataReceived += (s, e) => { }; p.ErrorDataReceived += (s, e) => { };
                            p.BeginOutputReadLine(); p.BeginErrorReadLine();
                            while (!p.HasExited)
                            {
                                if (my != videoGen) { try { p.Kill(); } catch { } return; }
                                long sz = 0;
                                foreach (var f in Directory.GetFiles(cache, id + ".v.*")) sz += new FileInfo(f).Length;
                                VideoMB = Math.Max(0.001, sz / 1048576.0);
                                Thread.Sleep(400);
                            }
                        }
                        file = done();
                        Prune(cache);
                    }
                    if (my != videoGen) return;
                    if (file == null) { VideoMB = 0; VideoFile = ""; return; }
                    // (relative to the game's user folder: the UI loads /temp/fernfahrer/videoaudio/<file>)
                    VideoFile = "temp/fernfahrer/videoaudio/" + Path.GetFileName(file);
                }
                catch (Exception e) { Status = "Video-Bild: " + e.Message; VideoMB = 0; }
            }) { IsBackground = true };
            th.Start();
        }

        double Target() { return VPos + (VPlay ? (DateTime.Now - VPosAt).TotalSeconds : 0); }

        // --- livestreams (Twitch, YouTube live, any .m3u8) – 2026-11-04 ------------------------------------------------
        // Media Foundation reads no HLS, and the game's UI may not fetch the stream itself (CORS, local://). So the helper
        // is the stream's client: yt-dlp gives the stream's playlist(s) – one with picture and sound (Twitch), or one each
        // (YouTube live: video only + audio only); the helper loads them every few seconds, fetches the new segments
        // (MPEG-TS or fMP4 with its init part), serves the picture's to the game's player on
        // http://127.0.0.1:47811/live.m3u8 (hls.js there) and decodes the sound from the sound's segments. In step by
        // the segments' clock (#EXT-X-PROGRAM-DATE-TIME): the player tells its playing date (vpos = Unix seconds).
        public volatile string LiveUrl = "", LiveFor = "";
        const int LIVE_PORT = 47811;
        class Seg { public long Seq; public double Dur, Pdt = double.NaN; public string Uri; public byte[] Data; }
        class Track
        {
            public readonly System.Collections.Generic.SortedDictionary<long, Seg> Segs = new System.Collections.Generic.SortedDictionary<long, Seg>();
            public string InitUri; public byte[] Init; public string Playlist = ""; public string Ext = ".ts";
        }
        readonly object liveLock = new object();
        Track vTrack = new Track(), aTrack;            // (aTrack: the sound's own playlist, or null = the picture's)
        System.Net.Sockets.TcpListener liveServer;
        int liveGen;

        static bool IsLiveLink(string u)
        {
            u = (u ?? "").ToLowerInvariant();
            if (u.Contains(".m3u8")) return true;
            if (u.Contains("twitch.tv/") && !u.Contains("/videos/") && !u.Contains("/clip")) return true;
            return u.Contains("youtube.com/live/") || (u.Contains("youtube.com/@") && u.Contains("/live"));
        }
        static readonly System.Collections.Generic.Dictionary<string, bool> ytLive = new System.Collections.Generic.Dictionary<string, bool>();
        static string RunYtDlp(string args, int timeoutMs)
        {
            string exe = Path.Combine(Path.GetDirectoryName(Application.ExecutablePath), "yt-dlp.exe");
            if (!File.Exists(exe)) throw new Exception("yt-dlp fehlt");
            var psi = new ProcessStartInfo(exe, args) { UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true, CreateNoWindow = true };
            using (var p = Process.Start(psi))
            {
                string o = p.StandardOutput.ReadToEnd(); string e = p.StandardError.ReadToEnd();
                p.WaitForExit(timeoutMs);
                if (string.IsNullOrWhiteSpace(o) && !string.IsNullOrWhiteSpace(e)) throw new Exception("yt-dlp: " + e.Split('\n')[0].Trim());
                return o ?? "";
            }
        }
        bool IsLive(string url)
        {
            if (IsLiveLink(url)) return true;
            string id = YtId(url);
            if (id == null) return false;
            bool l; if (ytLive.TryGetValue(id, out l)) return l;
            try { EnsureYtDlp(); l = RunYtDlp("--print is_live --skip-download --no-warnings \"https://www.youtube.com/watch?v=" + id + "\"", 30000).Trim() == "True"; }
            catch { l = false; }
            ytLive[id] = l;
            return l;
        }
        void EnsureYtDlp()
        {
            string exe = Path.Combine(Path.GetDirectoryName(Application.ExecutablePath), "yt-dlp.exe");
            if (File.Exists(exe)) return;
            Status = "lade yt-dlp (einmalig, ~18 MB) …";
            using (var wc = new System.Net.WebClient()) wc.DownloadFile("https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe", exe + ".part");
            File.Move(exe + ".part", exe);
        }
        static string Fetch(string url)
        {
            using (var wc = new System.Net.WebClient())
            {
                wc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Fernfahrer-Radio");
                wc.Encoding = System.Text.Encoding.UTF8;
                return wc.DownloadString(url);
            }
        }
        static byte[] FetchBytes(string url)
        {
            using (var wc = new System.Net.WebClient())
            {
                wc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Fernfahrer-Radio");
                return wc.DownloadData(url);
            }
        }
        static string Abs(string baseUrl, string rel) { return new Uri(new Uri(baseUrl), rel).ToString(); }
        // a master playlist gives its variant up to 720p (with sound when there is a choice)
        static string MediaPlaylist(string url)
        {
            string text = Fetch(url);
            if (!text.Contains("#EXT-X-STREAM-INF")) return url;
            string best = null, fallback = null; long bestBw = -1;
            var lines = text.Split('\n');
            for (int i = 0; i < lines.Length - 1; i++)
            {
                string l = lines[i].Trim();
                if (!l.StartsWith("#EXT-X-STREAM-INF")) continue;
                string uri = lines[i + 1].Trim();
                if (uri.StartsWith("#") || uri == "") continue;
                var mb = Regex.Match(l, "BANDWIDTH=(\\d+)"); long bw = mb.Success ? long.Parse(mb.Groups[1].Value) : 0;
                var mr = Regex.Match(l, "RESOLUTION=\\d+x(\\d+)"); int h = mr.Success ? int.Parse(mr.Groups[1].Value) : 0;
                if (l.Contains("audio_only") || h == 0) continue;
                fallback = fallback ?? uri;
                if (h <= 720 && bw > bestBw) { bestBw = bw; best = uri; }
            }
            return Abs(url, best ?? fallback ?? url);
        }
        static double ParseDate(string s)
        {
            DateTime d;
            if (DateTime.TryParse(s, System.Globalization.CultureInfo.InvariantCulture, System.Globalization.DateTimeStyles.AdjustToUniversal | System.Globalization.DateTimeStyles.AssumeUniversal, out d))
                return (d - new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc)).TotalSeconds;
            return double.NaN;
        }
        // one playlist kept: its newest segments fetched; for the picture also the playlist the game's player loads
        void LiveTrackLoop(Track tr, string media, bool forPlayer, int my)
        {
            bool first = true; long top = -1;              // (top: the newest segment fetched – only newer ones after it)
            while (!Stop && my == liveGen)
            {
                double target = 2;
                try
                {
                    string text = Fetch(media);
                    long seq = 0; double pdt = double.NaN, dur = 0;
                    var list = new System.Collections.Generic.List<Seg>();
                    foreach (var raw in text.Split('\n'))
                    {
                        string l = raw.Trim();
                        if (l.StartsWith("#EXT-X-MEDIA-SEQUENCE:")) long.TryParse(l.Substring(22), out seq);
                        else if (l.StartsWith("#EXT-X-TARGETDURATION:")) double.TryParse(l.Substring(22), System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out target);
                        else if (l.StartsWith("#EXT-X-PROGRAM-DATE-TIME:")) pdt = ParseDate(l.Substring(25));
                        else if (l.StartsWith("#EXT-X-MAP:"))
                        {
                            var mm = Regex.Match(l, "URI=\"([^\"]+)\"");
                            if (mm.Success) { string iu = Abs(media, mm.Groups[1].Value); if (tr.InitUri != iu) { tr.Init = FetchBytes(iu); tr.InitUri = iu; tr.Ext = ".m4s"; } }
                        }
                        else if (l.StartsWith("#EXTINF:")) { var m = Regex.Match(l, "#EXTINF:([0-9.]+)"); if (m.Success) double.TryParse(m.Groups[1].Value, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out dur); }
                        else if (l.Length > 0 && !l.StartsWith("#"))
                        {
                            list.Add(new Seg { Seq = seq, Dur = dur, Pdt = pdt, Uri = Abs(media, l) });
                            seq++;
                            if (!double.IsNaN(pdt)) pdt += dur;
                        }
                    }
                    if (list.Count > 0 && top >= 0 && list[list.Count - 1].Seq < top - 50) { top = -1; first = true; }   // (the stream started anew)
                    int startAt = first ? Math.Max(0, list.Count - 4) : 0;           // (at the start: the live edge)
                    first = false;
                    for (int i = startAt; i < list.Count && my == liveGen; i++)
                    {
                        var s = list[i];
                        if (s.Seq <= top) continue;
                        s.Data = FetchBytes(s.Uri);
                        top = s.Seq;
                        lock (liveLock)
                        {
                            tr.Segs[s.Seq] = s;
                            while (tr.Segs.Count > 24) { foreach (var k in tr.Segs.Keys) { tr.Segs.Remove(k); break; } }
                            if (forPlayer) tr.Playlist = BuildPlaylist(tr, target);
                        }
                    }
                    if (forPlayer && my == liveGen) { LiveUrl = "http://127.0.0.1:" + LIVE_PORT + "/live.m3u8"; Ok = true; Status = "Livestream läuft"; }
                }
                catch (Exception e) { Status = "Livestream: " + e.Message; }
                for (int i = 0; i < Math.Max(10, (int)(target * 5)) && !Stop && my == liveGen; i++) Thread.Sleep(100);   // (half a segment)
            }
        }
        static string BuildPlaylist(Track tr, double target)
        {
            var inv = System.Globalization.CultureInfo.InvariantCulture;
            var sb = new System.Text.StringBuilder("#EXTM3U\n#EXT-X-VERSION:" + (tr.Init != null ? "7" : "3") + "\n");
            sb.Append("#EXT-X-TARGETDURATION:" + Math.Ceiling(target).ToString(inv) + "\n");
            bool head = true; long prev = -1;
            foreach (var kv in tr.Segs)
            {
                if (head)
                {
                    sb.Append("#EXT-X-MEDIA-SEQUENCE:" + kv.Key + "\n");
                    if (tr.Init != null) sb.Append("#EXT-X-MAP:URI=\"init.mp4\"\n");
                    head = false;
                }
                if (prev >= 0 && kv.Key != prev + 1) sb.Append("#EXT-X-DISCONTINUITY\n");
                prev = kv.Key;
                if (!double.IsNaN(kv.Value.Pdt))
                    sb.Append("#EXT-X-PROGRAM-DATE-TIME:" + new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc).AddSeconds(kv.Value.Pdt).ToString("yyyy-MM-ddTHH:mm:ss.fffZ", inv) + "\n");
                sb.Append("#EXTINF:" + kv.Value.Dur.ToString("0.000", inv) + ",\nseg/" + kv.Key + tr.Ext + "\n");
            }
            return sb.ToString();
        }
        // the little web server for the game's player (only on this computer)
        void EnsureLiveServer()
        {
            if (liveServer != null) return;
            liveServer = new System.Net.Sockets.TcpListener(System.Net.IPAddress.Loopback, LIVE_PORT);
            liveServer.Start();
            var th = new Thread(() =>
            {
                while (!Stop)
                {
                    System.Net.Sockets.TcpClient c;
                    try { c = liveServer.AcceptTcpClient(); } catch { break; }
                    ThreadPool.QueueUserWorkItem(_ => ServeLive(c));
                }
            }) { IsBackground = true };
            th.Start();
        }
        void ServeLive(System.Net.Sockets.TcpClient c)
        {
            try
            {
                using (c)
                using (var ns = c.GetStream())
                {
                    var buf = new byte[4096]; int n = ns.Read(buf, 0, buf.Length);
                    string req = System.Text.Encoding.ASCII.GetString(buf, 0, Math.Max(0, n));
                    var m = Regex.Match(req, "^(GET|OPTIONS|HEAD) (\\S+)");
                    string path = m.Success ? m.Groups[2].Value : "";
                    byte[] body = new byte[0]; string type = "text/plain", status = "200 OK";
                    var tr = vTrack;
                    if (m.Success && m.Groups[1].Value == "OPTIONS") status = "204 No Content";
                    else if (path.StartsWith("/live.m3u8")) { lock (liveLock) body = System.Text.Encoding.UTF8.GetBytes(tr.Playlist); type = "application/vnd.apple.mpegurl"; }
                    else if (path.StartsWith("/init.mp4")) { lock (liveLock) body = tr.Init ?? new byte[0]; type = "video/mp4"; if (body.Length == 0) status = "404 Not Found"; }
                    else
                    {
                        var ms = Regex.Match(path, "^/seg/(\\d+)\\.(ts|m4s)");
                        Seg s = null;
                        if (ms.Success) lock (liveLock) tr.Segs.TryGetValue(long.Parse(ms.Groups[1].Value), out s);
                        if (s != null && s.Data != null) { body = s.Data; type = ms.Groups[2].Value == "ts" ? "video/mp2t" : "video/iso.segment"; } else status = "404 Not Found";
                    }
                    string head = "HTTP/1.1 " + status + "\r\nContent-Type: " + type + "\r\nContent-Length: " + body.Length +
                        "\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Headers: *\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n";
                    var hb = System.Text.Encoding.ASCII.GetBytes(head);
                    ns.Write(hb, 0, hb.Length);
                    if (m.Success && m.Groups[1].Value == "GET") ns.Write(body, 0, body.Length);
                }
            }
            catch { }
        }
        // the sound of the live stream: segment after segment decoded into the ring, kept on the player's clock
        void LiveSoundLoop(int dstRate, Ring ring, int my)
        {
            long next = -1; Resampler rs = null; int rsRate = 0;
            double pushedEpoch = double.NaN;
            while (!Stop && my == liveGen)
            {
                var tr = aTrack ?? vTrack;
                Seg s = null; byte[] init = null; string ext = ".ts";
                lock (liveLock)
                {
                    var segsNow = tr.Segs;
                    init = tr.Init; ext = tr.Init != null ? ".mp4" : ".ts";
                    if (segsNow.Count > 0)
                    {
                        if (next < 0) { int k = 0; foreach (var kv in segsNow) { if (k++ >= Math.Max(0, segsNow.Count - 3)) { next = kv.Key; break; } } }
                        // (the player far ahead of the sound: on to the segment holding its time)
                        double want = Target();
                        if (VPos > 1e9 && !double.IsNaN(pushedEpoch) && pushedEpoch - ring.Have / (double)dstRate < want - 2.5)
                            foreach (var kv in segsNow) if (!double.IsNaN(kv.Value.Pdt) && kv.Value.Pdt + kv.Value.Dur > want) { if (kv.Key > next) { next = kv.Key; ring.Clear(); } break; }
                        if (next >= 0 && !segsNow.ContainsKey(next)) { foreach (var kv in segsNow) if (kv.Key > next) { next = kv.Key; break; } }
                        segsNow.TryGetValue(next, out s);
                    }
                }
                if (s == null || s.Data == null) { Thread.Sleep(100); continue; }
                // (ahead of the player's picture, or the picture paused: wait)
                if (!VPlay) { Thread.Sleep(50); continue; }
                if (VPos > 1e9 && !double.IsNaN(s.Pdt))
                {
                    double heard = (double.IsNaN(pushedEpoch) ? s.Pdt : pushedEpoch) - ring.Have / (double)dstRate;
                    if (heard > Target() + 0.8) { Thread.Sleep(50); continue; }
                }
                if (ring.Have > dstRate * 2) { Thread.Sleep(50); continue; }
                try
                {
                    string tmp = Path.Combine(CacheDir(), "live_seg" + ext);
                    using (var fs = File.Create(tmp)) { if (init != null) fs.Write(init, 0, init.Length); fs.Write(s.Data, 0, s.Data.Length); }
                    int rate, ch; var rd = OpenStream(tmp, out rate, out ch);
                    if (rs == null || rsRate != rate) { rs = new Resampler(rate, dstRate, ring); rsRate = rate; }
                    long frames = 0; double ts; int fr;
                    double skip = (VPos > 1e9 && !double.IsNaN(s.Pdt)) ? Math.Max(0, Target() - s.Pdt) : 0;
                    long skipFrames = (long)(skip * rate);
                    while (my == liveGen && ReadBlockTs(rd, ch, (l, r) => { if (frames++ >= skipFrames) { Level = Level * 0.9995 + Math.Abs(l) * 0.0005; rs.Push(l, r); } }, out ts, out fr)) { }
                    Marshal.ReleaseComObject(rd);
                    pushedEpoch = double.IsNaN(s.Pdt) ? double.NaN : s.Pdt + s.Dur;
                }
                catch (Exception e) { Status = "Live-Ton: " + e.Message; }
                next = s.Seq + 1;
            }
        }
        void StartLive(string url, int dstRate, Ring ring)
        {
            int my = ++liveGen; ++gen;
            lock (liveLock) { vTrack = new Track(); aTrack = null; }
            LiveUrl = ""; LiveFor = url; VideoFile = ""; VideoFor = url; VideoMB = 0;
            var th = new Thread(() =>
            {
                try
                {
                    Status = "Livestream wird gesucht …"; Ok = false;
                    EnsureLiveServer();
                    string vUrl = url, aUrl = null;
                    if (!url.ToLowerInvariant().Contains(".m3u8"))
                    {
                        EnsureYtDlp();
                        // (picture and sound apart where the site has them so – YouTube live – else one with both)
                        var outp = RunYtDlp("-g -f \"bestvideo[height<=720][protocol*=m3u8]+bestaudio[protocol*=m3u8]/best[height<=720]/best\" --no-playlist --no-warnings \"" + url + "\"", 60000)
                            .Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);
                        if (outp.Length == 0 || !outp[0].StartsWith("http")) throw new Exception("kein Livestream gefunden (offline?)");
                        vUrl = outp[0].Trim();
                        if (outp.Length > 1 && outp[1].StartsWith("http")) aUrl = outp[1].Trim();
                    }
                    string vMedia = MediaPlaylist(vUrl);
                    if (aUrl != null) { lock (liveLock) aTrack = new Track(); }
                    var snd = new Thread(() => LiveSoundLoop(dstRate, ring, my)) { IsBackground = true };
                    snd.SetApartmentState(ApartmentState.MTA);
                    snd.Start();
                    if (aUrl != null)
                    {
                        var at = aTrack;
                        var ath = new Thread(() => LiveTrackLoop(at, aUrl, false, my)) { IsBackground = true };
                        ath.Start();
                    }
                    LiveTrackLoop(vTrack, vMedia, true, my);
                }
                catch (Exception e) { Status = "Livestream: " + e.Message; Ok = false; }
            }) { IsBackground = true };
            th.SetApartmentState(ApartmentState.MTA);
            th.Start();
        }

        void StartVideo(string url, int dstRate, Ring ring)
        {
            int my = ++gen;
            var th = new Thread(() =>
            {
                while (!Stop && my == gen)
                {
                    try
                    {
                        Status = "Video-Ton wird geladen …"; Ok = false;
                        string audio = ResolveAudio(url);
                        FetchVideo(url);                                 // (the picture alongside, for the game's player)
                        int rate, ch; IMFSourceReader rd;
                        try { rd = OpenStream(audio, out rate, out ch); }
                        catch (Exception)
                        {
                            if (!audio.StartsWith("http")) throw;
                            audio = Download(audio); rd = OpenStream(audio, out rate, out ch);
                        }
                        var rs = new Resampler(rate, dstRate, ring);
                        double decodedTo = 0; DateTime checkAt = DateTime.MinValue;
                        ring.Clear();
                        if (Target() > 0.5) { Seek(rd, Target()); decodedTo = Target(); }
                        Status = "Video-Ton läuft"; Ok = true;
                        while (!Stop && my == gen)
                        {
                            // (in step with the picture: once a second; the sound heard = decoded minus what waits in the ring)
                            if ((DateTime.Now - checkAt).TotalSeconds > 1)
                            {
                                checkAt = DateTime.Now;
                                double heard = decodedTo - ring.Have / (double)dstRate, want = Target();
                                if (Math.Abs(heard - want) > 1.5) { ring.Clear(); Seek(rd, want); decodedTo = want; }
                            }
                            if (!VPlay || ring.Have > dstRate * 1) { Thread.Sleep(20); continue; }
                            double ts; int frames;
                            if (!ReadBlockTs(rd, ch, (l, r) => { Level = Level * 0.9995 + Math.Abs(l) * 0.0005; rs.Push(l, r); }, out ts, out frames))
                            {
                                // (the end: silence until the picture jumps back – then a seek)
                                Status = "Video zu Ende"; Thread.Sleep(200); continue;
                            }
                            if (ts >= 0) decodedTo = ts + frames / (double)rate;
                        }
                        Marshal.ReleaseComObject(rd);
                    }
                    catch (Exception e) { Status = "Video: " + e.Message; Ok = false; }
                    for (int i = 0; i < 30 && !Stop && my == gen; i++) Thread.Sleep(100);
                }
            }) { IsBackground = true };
            th.SetApartmentState(ApartmentState.MTA);
            th.Start();
        }

        void StartRadio(string url, int dstRate, Ring ring)
        {
            int my = ++gen;
            var th = new Thread(() =>
            {
                while (!Stop && my == gen)
                {
                    try
                    {
                        Status = "verbinde …"; Ok = false;
                        int rate, ch; var rd = OpenStream(url, out rate, out ch);
                        var rs = new Resampler(rate, dstRate, ring);
                        Status = "Radio läuft"; Ok = true;
                        while (!Stop && my == gen)
                        {
                            if (ring.Have > dstRate * 2) { Thread.Sleep(20); continue; }
                            if (!ReadBlock(rd, ch, (l, r) => { Level = Level * 0.9995 + Math.Abs(l) * 0.0005; rs.Push(l, r); })) throw new Exception("Stream abgebrochen");
                        }
                        Marshal.ReleaseComObject(rd);
                    }
                    catch (Exception e) { Status = "Radio: " + e.Message; Ok = false; }
                    for (int i = 0; i < 30 && !Stop && my == gen; i++) Thread.Sleep(100);     // (3 s, then again)
                }
            }) { IsBackground = true };
            th.SetApartmentState(ApartmentState.MTA);
            th.Start();
        }

        // --- the loop for one source; returns when the game picks another ---
        public void Run()
        {
            string src = Src, url = Url;
            if (src == "idle" || src == "spotify")
            {
                Level = 0;
                if (src == "idle") { RestorePlayers(); Ok = false; Title = ""; }
                Status = src == "idle" ? "bereit (wartet auf das Spiel)" : "Spotify-Lautstärke";
                DateTime tAt = DateTime.MinValue;
                while (!Stop && Src == src)
                {
                    ReadState();
                    if (src == "spotify")
                    {
                        gain += (gainT - gain) * 0.25;
                        SetPlayers((float)gain);
                        if ((DateTime.Now - tAt).TotalSeconds > 1.5)
                        {
                            tAt = DateTime.Now; string t = SpotifyTitle();
                            Title = t ?? ""; Status = t == null ? (Ok ? "Player läuft" : "kein Musikprogramm offen") : (t == "" ? "Spotify pausiert" : "Spotify spielt");
                        }
                    }
                    Thread.Sleep(50);
                }
                if (src == "spotify") RestorePlayers();
                return;
            }
            RestorePlayers();
            Title = "";
            var en = (IMMDeviceEnumerator)new MMDeviceEnumeratorCo();
            IMMDevice dst; en.GetDefaultAudioEndpoint(eRender, eConsole, out dst);
            object o;
            Marshal.ThrowExceptionForHR(dst.Activate(ref IID_AudioClient, CLSCTX_ALL, IntPtr.Zero, out o)); var renC = (IAudioClient)o;
            IntPtr df; renC.GetMixFormat(out df); var rf = Fmt.Read(df);
            Marshal.ThrowExceptionForHR(renC.Initialize(SHARED, 0, 1000000, 0, df, IntPtr.Zero));
            int renFrames; renC.GetBufferSize(out renFrames);
            renC.GetService(ref IID_Render, out o); var ren = (IAudioRenderClient)o;
            var ring = new Ring(rf.Rate * 3);

            IAudioClient capC = null; IAudioCaptureClient cap = null; Fmt cf = null; Resampler capRs = null;
            if (src == "line")
            {
                IMMDevice s = FindRender(en, SourceName);
                if (s == null) { Status = "„" + SourceName + "“ nicht gefunden"; Ok = false; WaitWhile(src); return; }
                if (NameOf(dst).IndexOf(SourceName, StringComparison.OrdinalIgnoreCase) >= 0) { Status = "Standardausgabe ist selbst „" + SourceName + "“"; Ok = false; WaitWhile(src); return; }
                Marshal.ThrowExceptionForHR(s.Activate(ref IID_AudioClient, CLSCTX_ALL, IntPtr.Zero, out o)); capC = (IAudioClient)o;
                IntPtr pf; capC.GetMixFormat(out pf); cf = Fmt.Read(pf);
                Marshal.ThrowExceptionForHR(capC.Initialize(SHARED, LOOPBACK, 2000000, 0, pf, IntPtr.Zero));
                capC.GetService(ref IID_Capture, out o); cap = (IAudioCaptureClient)o;
                capRs = new Resampler(cf.Rate, rf.Rate, ring);
                capC.Start(); Status = "Line läuft"; Ok = true;
            }
            else if (src == "video" && IsLive(url)) StartLive(url, rf.Rate, ring);
            else if (src == "video") { LiveUrl = ""; LiveFor = ""; StartVideo(url, rf.Rate, ring); }
            else StartRadio(url, rf.Rate, ring);

            var fx = new Fx(rf.Rate); bool playing = false;
            renC.Start();
            try
            {
                while (!Stop && Src == src && ((src != "radio" && src != "video") || Url == url))
                {
                    ReadState();
                    fx.Target(mode, stVol, stDist, stDuck, src == "line");
                    fx.Eq(stB, stM, stT);
                    if (cap != null)
                    {
                        int pkt; cap.GetNextPacketSize(out pkt);
                        while (pkt > 0)
                        {
                            IntPtr data; int frames, flags; long dp, qp;
                            if (cap.GetBuffer(out data, out frames, out flags, out dp, out qp) != 0) break;
                            bool silent = (flags & 2) != 0;
                            for (int i = 0; i < frames; i++)
                            {
                                float l = silent ? 0 : Sample(data, i * cf.Channels, cf);
                                float r = silent ? 0 : (cf.Channels > 1 ? Sample(data, i * cf.Channels + 1, cf) : l);
                                Level = Level * 0.9995 + Math.Abs(l) * 0.0005;
                                capRs.Push(l, r);
                            }
                            cap.ReleaseBuffer(frames);
                            cap.GetNextPacketSize(out pkt);
                        }
                        ring.Trim(rf.Rate / 5);                              // (the delay stays under 200 ms)
                        playing = true;
                    }
                    else
                    {
                        // (a station: half a second in hand before it plays, again after a dropout)
                        // (the video: a short cushion only – it should start with the picture – and held while paused)
                        int cushion = src == "video" ? rf.Rate / 8 : rf.Rate / 2;
                        if (!playing && ring.Have > cushion) playing = true;
                        if (playing && ring.Have == 0) playing = false;
                        if (src == "video" && !VPlay) playing = false;
                    }
                    int pad; renC.GetCurrentPadding(out pad);
                    int free = renFrames - pad;
                    if (free > 0)
                    {
                        IntPtr outp; if (ren.GetBuffer(free, out outp) != 0) { Thread.Sleep(8); continue; }
                        fx.Block();
                        for (int i = 0; i < free; i++)
                        {
                            float l = 0, r = 0;
                            if (playing) ring.Pop(out l, out r);
                            fx.Run(ref l, ref r);
                            for (int c = 0; c < rf.Channels; c++) Put(outp, i * rf.Channels + c, rf, c == 0 ? l : c == 1 ? r : 0f);
                        }
                        ren.ReleaseBuffer(free, 0);
                    }
                    Thread.Sleep(8);
                }
            }
            finally
            {
                gen++; liveGen++;                                        // (the station's thread ends)
                if (capC != null) capC.Stop();
                renC.Stop();
            }
        }
        void WaitWhile(string src) { while (!Stop && Src == src) { ReadState(); Thread.Sleep(100); } }

        // (checks) 8 s of a station through each mode's sound, written as WAV files beside it, with level figures
        public static void FxTest(string url, string outDir)
        {
            int rate, ch; var rd = OpenStream(url, out rate, out ch);
            var src = new List<float>();
            var t0 = DateTime.Now;
            while (src.Count < rate * 8 * 2 && (DateTime.Now - t0).TotalSeconds < 25) if (!ReadBlock(rd, ch, (l, r) => { src.Add(l); src.Add(r); })) break;
            var modes = new[] { new[] { "dry", "0" }, new[] { "cab", "0" }, new[] { "outside", "0" }, new[] { "walk", "10" }, new[] { "walk", "30" }, new[] { "cabBass", "0" }, new[] { "cabTreble", "0" } };
            foreach (var m0 in modes)
            {
                var m = m0;
                var fx = new Fx(rate);
                if (m[0] == "cabBass") { fx.Eq(9, 0, -6); m = new[] { "cab", "0", "eqBass" }; }
                if (m[0] == "cabTreble") { fx.Eq(-6, 0, 9); m = new[] { "cab", "0", "eqTreble" }; }
                bool dry = m[0] == "dry";
                fx.Target(dry ? "normal" : m[0], 1, double.Parse(m[1]), false, true);
                fx.Gain = fx.GainT; fx.Low = fx.LowT; fx.High = fx.HighT; fx.Boom = fx.BoomT; fx.Pres = fx.PresT; fx.Drive = fx.DriveT; fx.Wet = fx.WetT; fx.Wow = fx.WowT;
                var outp = new short[src.Count]; double sum = 0, peak = 0, diff = 0; float pl = 0;
                for (int i = 0; i + 1 < src.Count; i += 2)
                {
                    if (i % 512 == 0) fx.Block();
                    float l = src[i], r = src[i + 1]; fx.Run(ref l, ref r);
                    sum += l * l; peak = Math.Max(peak, Math.Abs(l)); diff += (l - pl) * (l - pl); pl = l;
                    outp[i] = (short)(Math.Max(-1, Math.Min(1, l)) * 32767); outp[i + 1] = (short)(Math.Max(-1, Math.Min(1, r)) * 32767);
                }
                int n = src.Count / 2; double rms = Math.Sqrt(sum / n);
                // (brightness: the share of change from sample to sample – high for treble, low for a dull sound)
                string tag = m.Length > 2 ? m[2] : m[0];
                Console.WriteLine(string.Format(System.Globalization.CultureInfo.InvariantCulture, "{0,-9} {1,3} m  rms {2:0.000}  peak {3:0.000}  brightness {4:0.000}", tag, m[1], rms, peak, Math.Sqrt(diff / n) / Math.Max(1e-6, rms)));
                string f = Path.Combine(outDir, "fx_" + tag + "_" + m[1] + ".wav");
                using (var w = new BinaryWriter(File.Create(f)))
                {
                    w.Write(new[] { 'R', 'I', 'F', 'F' }); w.Write(36 + outp.Length * 2); w.Write(new[] { 'W', 'A', 'V', 'E', 'f', 'm', 't', ' ' });
                    w.Write(16); w.Write((short)1); w.Write((short)2); w.Write(rate); w.Write(rate * 4); w.Write((short)4); w.Write((short)16);
                    w.Write(new[] { 'd', 'a', 't', 'a' }); w.Write(outp.Length * 2); foreach (var s in outp) w.Write(s);
                }
            }
        }

        // (checks) a station decoded for 4 s: its level
        public static void Probe(string url)
        {
            try
            {
                int rate, ch; var rd = OpenStream(url, out rate, out ch);
                double lvl = 0; long n = 0; var t0 = DateTime.Now;
                while (n < rate * 4 && (DateTime.Now - t0).TotalSeconds < 15)
                    if (!ReadBlock(rd, ch, (l, r) => { lvl += Math.Abs(l); n++; })) break;
                Console.WriteLine("OK " + rate + " Hz " + ch + " ch, " + n + " frames, level " + (n > 0 ? lvl / n : 0).ToString("0.000"));
            }
            catch (Exception e) { Console.WriteLine("FAIL " + e.Message); }
        }
    }

    static class Program
    {
        [STAThread]
        static void Main(string[] args)
        {
            // (TLS 1.2 for every download – .NET 4 offers an old one by default: "no secure channel")
            try { System.Net.ServicePointManager.SecurityProtocol = (System.Net.SecurityProtocolType)(3072 | 768); } catch { }
            if (args.Length > 1 && args[0] == "--probe") { Engine.Probe(args[1]); return; }
            if (args.Length > 0 && args[0] == "--sessions") { Engine.ListSessions(); return; }
            if (args.Length > 1 && args[0] == "--routetest")
            {
                var tt = new Thread(() => { try { Engine.RouteTest(int.Parse(args[1])); } catch (Exception e) { Console.WriteLine("FAIL " + e.Message); } });
                tt.SetApartmentState(ApartmentState.MTA); tt.Start(); tt.Join(); return;
            }
            if (args.Length > 2 && args[0] == "--plbtest")
            {
                var tt = new Thread(() => Engine.PlbTest(int.Parse(args[1]), float.Parse(args[2], System.Globalization.CultureInfo.InvariantCulture)));
                tt.SetApartmentState(ApartmentState.MTA); tt.Start(); tt.Join(); return;
            }
            if (args.Length > 2 && args[0] == "--fxtest") { Engine.FxTest(args[1], args[2]); return; }
            bool first;
            using (var mx = new Mutex(true, "FernfahrerRadioSingle", out first))
            {
                if (!first) return;                                  // (one at a time)
                string dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "BeamNG", "BeamNG.drive", "current", "settings", "fernfahrer");
                Directory.CreateDirectory(dir);
                var eng = new Engine { StateFile = Path.Combine(dir, "radio_state.json"), HeartbeatFile = Path.Combine(dir, "radio_helper.json") };
                if (args.Length > 0) eng.SourceName = args[0];
                var th = new Thread(() =>
                {
                    while (!eng.Stop)
                    {
                        try { eng.ReadState(); eng.Run(); }
                        catch (Exception e) { eng.Status = "Fehler: " + e.Message; eng.Ok = false; eng.Beat(); if (!eng.Stop) Thread.Sleep(3000); }
                    }
                    eng.RestorePlayers();
                }) { IsBackground = true, Priority = ThreadPriority.AboveNormal };
                th.SetApartmentState(ApartmentState.MTA);
                th.Start();

                var tray = new NotifyIcon { Icon = SystemIcons.Information, Visible = true, Text = "Fernfahrer-Radio" };
                var menu = new ContextMenu();
                var info = new MenuItem("Status …") { Enabled = false };
                menu.MenuItems.Add(info);
                menu.MenuItems.Add("-");
                menu.MenuItems.Add("Beenden", (s, e) => { eng.Stop = true; th.Join(1500); tray.Visible = false; Application.Exit(); });
                menu.Popup += (s, e) => { info.Text = eng.Src + ": " + eng.Status; };
                tray.ContextMenu = menu;
                var timer = new System.Windows.Forms.Timer { Interval = 2000 };
                timer.Tick += (s, e) => { string t = "Fernfahrer-Radio: " + eng.Status; tray.Text = t.Substring(0, Math.Min(63, t.Length)); };
                timer.Start();
                tray.ShowBalloonTip(4000, "Fernfahrer-Radio", "Läuft. Quelle wählst du im Spiel in der Kabinen-App.", ToolTipIcon.Info);
                Application.Run();
                eng.Stop = true;
                th.Join(1500);
                eng.RestorePlayers();
            }
        }
    }
}
