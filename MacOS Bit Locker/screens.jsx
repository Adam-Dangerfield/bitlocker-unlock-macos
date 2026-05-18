// screens.jsx — All 6 screens of the BitLocker Unlock macOS app.
// Each screen renders inside a <Window> that paints the macOS chrome.
// Light/dark switched by a `dark` prop threaded down.

const TOKENS = {
  light: {
    chrome: '#ECECEC',       // titlebar / vibrancy
    chromeBorder: 'rgba(0,0,0,0.18)',
    body: '#F6F6F6',         // window body
    card: '#FFFFFF',
    cardBorder: 'rgba(0,0,0,0.08)',
    cardShadow: '0 1px 0 rgba(0,0,0,0.04), 0 1px 3px rgba(0,0,0,0.06)',
    text: '#1D1D1F',
    textDim: 'rgba(60,60,67,0.7)',
    textFaint: 'rgba(60,60,67,0.45)',
    divider: 'rgba(0,0,0,0.08)',
    fieldBg: '#FFFFFF',
    fieldBorder: 'rgba(0,0,0,0.14)',
    fieldShadow: 'inset 0 1px 0 rgba(0,0,0,0.04)',
    segBg: 'rgba(0,0,0,0.06)',
    segActive: '#FFFFFF',
    accent: '#007AFF',
    success: '#34C759',
    error: '#FF3B30',
    warn: '#FF9500',
    sheetBg: '#F6F6F6',
    sheetShadow: '0 20px 50px rgba(0,0,0,0.18), 0 0 0 0.5px rgba(0,0,0,0.2)',
    backdrop: 'rgba(0,0,0,0.20)',
    progressTrack: 'rgba(0,0,0,0.08)',
    iconBg: 'rgba(0,122,255,0.10)',
    iconBgErr: 'rgba(255,59,48,0.12)',
    iconBgOk: 'rgba(52,199,89,0.14)',
  },
  dark: {
    chrome: '#2A2A2C',
    chromeBorder: 'rgba(255,255,255,0.10)',
    body: '#1E1E20',
    card: '#2C2C2E',
    cardBorder: 'rgba(255,255,255,0.06)',
    cardShadow: '0 1px 0 rgba(255,255,255,0.04), 0 1px 3px rgba(0,0,0,0.5)',
    text: '#F5F5F7',
    textDim: 'rgba(235,235,245,0.6)',
    textFaint: 'rgba(235,235,245,0.35)',
    divider: 'rgba(255,255,255,0.08)',
    fieldBg: '#1C1C1E',
    fieldBorder: 'rgba(255,255,255,0.10)',
    fieldShadow: 'inset 0 1px 0 rgba(0,0,0,0.4)',
    segBg: 'rgba(255,255,255,0.06)',
    segActive: '#48484A',
    accent: '#0A84FF',
    success: '#30D158',
    error: '#FF453A',
    warn: '#FF9F0A',
    sheetBg: '#2C2C2E',
    sheetShadow: '0 20px 50px rgba(0,0,0,0.6), 0 0 0 0.5px rgba(255,255,255,0.08)',
    backdrop: 'rgba(0,0,0,0.45)',
    progressTrack: 'rgba(255,255,255,0.10)',
    iconBg: 'rgba(10,132,255,0.18)',
    iconBgErr: 'rgba(255,69,58,0.20)',
    iconBgOk: 'rgba(48,209,88,0.20)',
  },
};

const SF = '-apple-system, BlinkMacSystemFont, "SF Pro Text", "SF Pro Display", "Helvetica Neue", Helvetica, Arial, sans-serif';
const SFMONO = '"SF Mono", "JetBrains Mono", ui-monospace, Menlo, monospace';

// ─── primitives ───────────────────────────────────────────────────────

function TrafficLights({ active = true }) {
  const dots = [
    { fill: active ? '#FF5F57' : '#C0C0C0', border: '#E0443E' },
    { fill: active ? '#FEBC2E' : '#C0C0C0', border: '#DEA123' },
    { fill: active ? '#28C840' : '#C0C0C0', border: '#1AAB29' },
  ];
  return (
    <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
      {dots.map((d, i) => (
        <span key={i} style={{
          width: 12, height: 12, borderRadius: 999,
          background: d.fill,
          boxShadow: `inset 0 0 0 0.5px ${d.border}`,
        }} />
      ))}
    </div>
  );
}

function GearIcon({ color }) {
  return (
    <svg width="15" height="15" viewBox="0 0 16 16" fill="none">
      <path d="M8 5.5a2.5 2.5 0 100 5 2.5 2.5 0 000-5z" stroke={color} strokeWidth="1.2" />
      <path d="M8 1.5v1.6M8 12.9v1.6M3.4 3.4l1.1 1.1M11.5 11.5l1.1 1.1M1.5 8h1.6M12.9 8h1.6M3.4 12.6l1.1-1.1M11.5 4.5l1.1-1.1"
            stroke={color} strokeWidth="1.2" strokeLinecap="round" />
    </svg>
  );
}

function Window({ dark, title = 'BitLocker Unlock', children, hasOverlay }) {
  const t = TOKENS[dark ? 'dark' : 'light'];
  return (
    <div style={{
      width: 520, height: 640,
      borderRadius: 11,
      background: t.body,
      color: t.text,
      fontFamily: SF,
      fontSize: 13,
      lineHeight: 1.35,
      boxShadow: dark
        ? '0 22px 50px rgba(0,0,0,0.55), 0 0 0 0.5px rgba(255,255,255,0.10)'
        : '0 22px 50px rgba(0,0,0,0.18), 0 0 0 0.5px rgba(0,0,0,0.10)',
      overflow: 'hidden',
      position: 'relative',
      WebkitFontSmoothing: 'antialiased',
    }}>
      {/* Titlebar */}
      <div style={{
        height: 38,
        background: t.chrome,
        borderBottom: `0.5px solid ${t.chromeBorder}`,
        display: 'flex', alignItems: 'center',
        padding: '0 14px',
        position: 'relative',
      }}>
        <TrafficLights />
        <div style={{
          position: 'absolute', left: 0, right: 0, top: 0, bottom: 0,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          fontSize: 13, fontWeight: 600, color: t.text, pointerEvents: 'none',
        }}>{title}</div>
        <div style={{ marginLeft: 'auto', display: 'flex', alignItems: 'center' }}>
          <button style={{
            width: 24, height: 24, borderRadius: 5, border: 'none',
            background: 'transparent', cursor: 'pointer',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}>
            <GearIcon color={t.textDim} />
          </button>
        </div>
      </div>
      {/* Body */}
      <div style={{
        position: 'absolute', top: 38, left: 0, right: 0, bottom: 0,
        background: t.body,
      }}>
        {children}
      </div>
      {hasOverlay}
    </div>
  );
}

function Button({ variant = 'secondary', dark, children, full, disabled, style = {} }) {
  const t = TOKENS[dark ? 'dark' : 'light'];
  const base = {
    height: 28, padding: '0 14px',
    borderRadius: 6, border: 'none',
    fontFamily: SF, fontSize: 13, fontWeight: 500,
    cursor: 'pointer',
    display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
    minWidth: 76,
    width: full ? '100%' : undefined,
    opacity: disabled ? 0.5 : 1,
    ...style,
  };
  if (variant === 'primary') {
    return <button style={{
      ...base,
      background: t.accent, color: '#fff',
      boxShadow: `inset 0 0.5px 0 rgba(255,255,255,0.30), 0 0.5px 1px rgba(0,0,0,0.10)`,
    }}>{children}</button>;
  }
  if (variant === 'destructive') {
    return <button style={{
      ...base,
      background: t.card, color: t.error,
      boxShadow: `inset 0 0 0 0.5px ${t.fieldBorder}`,
    }}>{children}</button>;
  }
  // secondary
  return <button style={{
    ...base,
    background: dark ? '#48484A' : '#FFFFFF',
    color: t.text,
    boxShadow: `inset 0 0 0 0.5px ${dark ? 'rgba(255,255,255,0.12)' : 'rgba(0,0,0,0.16)'}, 0 0.5px 1px rgba(0,0,0,0.06)`,
  }}>{children}</button>;
}

function LinkText({ dark, children, style }) {
  const t = TOKENS[dark ? 'dark' : 'light'];
  return <span style={{ color: t.accent, cursor: 'pointer', ...style }}>{children}</span>;
}

// ─── icons (USB + lock, checkmark, error) ─────────────────────────────

function UsbLockIcon({ dark, size = 92, state = 'locked' }) {
  const t = TOKENS[dark ? 'dark' : 'light'];
  // USB drive silhouette with a tiny padlock badge in the bottom right.
  const bodyFill = dark ? '#3A3A3C' : '#E8E8EA';
  const bodyStroke = dark ? 'rgba(255,255,255,0.12)' : 'rgba(0,0,0,0.10)';
  const connectorFill = dark ? '#48484A' : '#D6D6D8';
  const accent = state === 'error' ? t.error : state === 'mounted' ? t.success : t.accent;
  return (
    <svg width={size} height={size} viewBox="0 0 96 96" fill="none">
      {/* connector */}
      <rect x="38" y="10" width="20" height="18" rx="2" fill={connectorFill} stroke={bodyStroke} />
      <rect x="42" y="14" width="4" height="6" fill={dark ? '#1E1E20' : '#fff'} />
      <rect x="50" y="14" width="4" height="6" fill={dark ? '#1E1E20' : '#fff'} />
      {/* shaft */}
      <rect x="40" y="26" width="16" height="6" fill={connectorFill} />
      {/* body */}
      <rect x="26" y="32" width="44" height="54" rx="6" fill={bodyFill} stroke={bodyStroke} />
      {/* label area */}
      <rect x="32" y="40" width="32" height="16" rx="2" fill={dark ? '#2C2C2E' : '#fff'} stroke={bodyStroke} />
      <rect x="35" y="44" width="14" height="2" rx="1" fill={dark ? 'rgba(255,255,255,0.25)' : 'rgba(0,0,0,0.2)'} />
      <rect x="35" y="49" width="22" height="2" rx="1" fill={dark ? 'rgba(255,255,255,0.18)' : 'rgba(0,0,0,0.14)'} />
      {/* led */}
      <circle cx="48" cy="64" r="1.8" fill={accent} />
      {/* padlock badge */}
      <g transform="translate(54,58)">
        <circle r="14" fill={accent} />
        {state === 'mounted' ? (
          <path d="M-5 0 L-1.5 3.5 L5 -3.5" stroke="#fff" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" fill="none" />
        ) : state === 'error' ? (
          <g>
            <path d="M-4 -4 L4 4 M4 -4 L-4 4" stroke="#fff" strokeWidth="2.2" strokeLinecap="round" />
          </g>
        ) : (
          <g>
            <rect x="-4" y="-1" width="8" height="7" rx="1.2" fill="#fff" />
            <path d="M-2.5 -1 V-3.5 a2.5 2.5 0 015 0 V-1" stroke="#fff" strokeWidth="1.4" fill="none" strokeLinecap="round" />
          </g>
        )}
      </g>
    </svg>
  );
}

function SmallUsbIcon({ dark, size = 36 }) {
  const bodyFill = dark ? '#48484A' : '#E8E8EA';
  const stroke = dark ? 'rgba(255,255,255,0.15)' : 'rgba(0,0,0,0.12)';
  return (
    <svg width={size} height={size} viewBox="0 0 36 36" fill="none">
      <rect x="14" y="3" width="8" height="6" rx="1" fill={dark ? '#5A5A5C' : '#D6D6D8'} stroke={stroke}/>
      <rect x="11" y="8" width="14" height="22" rx="2.5" fill={bodyFill} stroke={stroke}/>
      <rect x="14" y="12" width="8" height="5" rx="1" fill={dark ? '#2C2C2E' : '#fff'} stroke={stroke}/>
    </svg>
  );
}

// ─── 1. EMPTY STATE ───────────────────────────────────────────────────
function ScreenEmpty({ dark }) {
  const t = TOKENS[dark ? 'dark' : 'light'];
  return (
    <div style={{ height: '100%', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', padding: '0 56px', textAlign: 'center', position: 'relative' }}>
      <div style={{ opacity: 0.92 }}>
        <UsbLockIcon dark={dark} size={108} state="locked" />
      </div>
      <div style={{ height: 24 }} />
      <div style={{ fontSize: 20, fontWeight: 600, letterSpacing: -0.2 }}>Plug in a BitLocker drive</div>
      <div style={{ height: 6 }} />
      <div style={{ color: t.textDim, fontSize: 13 }}>We'll detect it automatically.</div>
      <div style={{ position: 'absolute', bottom: 28, left: 0, right: 0, textAlign: 'center', fontSize: 12 }}>
        <LinkText dark={dark}>Pick a drive manually…</LinkText>
      </div>
    </div>
  );
}

// ─── 2. DRIVE DETECTED ────────────────────────────────────────────────
function DriveCard({ dark, locked = true }) {
  const t = TOKENS[dark ? 'dark' : 'light'];
  return (
    <div style={{
      background: t.card,
      border: `0.5px solid ${t.cardBorder}`,
      borderRadius: 10,
      padding: 16,
      boxShadow: t.cardShadow,
      display: 'flex', gap: 14, alignItems: 'center',
    }}>
      <SmallUsbIcon dark={dark} size={44} />
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: 14, fontWeight: 600 }}>Kingston DataTraveler</div>
        <div style={{ fontSize: 12, color: t.textDim, marginTop: 2 }}>
          128.3 GB · <span style={{ fontFamily: SFMONO, fontSize: 11.5 }}>/dev/disk4s2</span>
        </div>
        <div style={{
          display: 'inline-flex', alignItems: 'center', gap: 6, marginTop: 7,
          fontSize: 11.5, color: t.warn, fontWeight: 500,
        }}>
          <span style={{ width: 6, height: 6, borderRadius: 999, background: t.warn, display: 'inline-block' }} />
          Locked — BitLocker
        </div>
      </div>
    </div>
  );
}

function ScreenDetected({ dark }) {
  const t = TOKENS[dark ? 'dark' : 'light'];
  return (
    <div style={{ height: '100%', display: 'flex', flexDirection: 'column', padding: '36px 28px 24px' }}>
      <div style={{ fontSize: 11, fontWeight: 600, textTransform: 'uppercase', letterSpacing: 0.6, color: t.textDim, marginBottom: 10 }}>
        Detected drive
      </div>
      <DriveCard dark={dark} />
      <div style={{ flex: 1 }} />
      <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
        <Button dark={dark} variant="primary" full>Unlock</Button>
        <Button dark={dark} variant="secondary" full>Pick a different drive</Button>
      </div>
    </div>
  );
}

// ─── 3. UNLOCK SHEET ──────────────────────────────────────────────────
function Segmented({ dark, options, value, onChange }) {
  const t = TOKENS[dark ? 'dark' : 'light'];
  return (
    <div style={{
      display: 'grid', gridTemplateColumns: `repeat(${options.length},1fr)`,
      padding: 2, background: t.segBg,
      borderRadius: 7, fontSize: 12, fontWeight: 500,
    }}>
      {options.map((opt) => {
        const active = opt === value;
        return (
          <div key={opt} style={{
            padding: '5px 0', textAlign: 'center',
            background: active ? t.segActive : 'transparent',
            color: t.text,
            borderRadius: 5,
            boxShadow: active ? (dark ? '0 0 0 0.5px rgba(255,255,255,0.12), 0 1px 2px rgba(0,0,0,0.3)' : '0 0 0 0.5px rgba(0,0,0,0.08), 0 1px 2px rgba(0,0,0,0.08)') : 'none',
          }}>{opt}</div>
        );
      })}
    </div>
  );
}

function Field({ dark, value, mask, mono, placeholder, focused }) {
  const t = TOKENS[dark ? 'dark' : 'light'];
  return (
    <div style={{
      height: 28,
      background: t.fieldBg,
      borderRadius: 6,
      border: `0.5px solid ${focused ? t.accent : t.fieldBorder}`,
      boxShadow: focused ? `0 0 0 3px ${dark ? 'rgba(10,132,255,0.35)' : 'rgba(0,122,255,0.25)'}` : t.fieldShadow,
      display: 'flex', alignItems: 'center', padding: '0 9px',
      fontFamily: mono ? SFMONO : SF, fontSize: 13,
      color: value ? t.text : t.textFaint,
      letterSpacing: mask ? 2 : 0,
    }}>
      {value || placeholder}
    </div>
  );
}

function Checkbox({ dark, checked, label }) {
  const t = TOKENS[dark ? 'dark' : 'light'];
  return (
    <label style={{ display: 'inline-flex', alignItems: 'center', gap: 7, fontSize: 12, color: t.text, cursor: 'pointer' }}>
      <span style={{
        width: 14, height: 14, borderRadius: 3,
        background: checked ? t.accent : t.fieldBg,
        border: `0.5px solid ${checked ? t.accent : t.fieldBorder}`,
        display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
      }}>
        {checked && <svg width="9" height="9" viewBox="0 0 10 10"><path d="M1.5 5L4 7.5 8.5 2.5" stroke="#fff" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" fill="none"/></svg>}
      </span>
      {label}
    </label>
  );
}

function UnlockSheet({ dark, method = 'Recovery key' }) {
  const t = TOKENS[dark ? 'dark' : 'light'];
  return (
    <div style={{
      position: 'absolute', inset: 0,
      background: t.backdrop,
      display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'flex-start',
      paddingTop: 12,
    }}>
      <div style={{
        width: 460,
        background: t.sheetBg,
        borderRadius: '0 0 8px 8px',
        boxShadow: t.sheetShadow,
        padding: '22px 24px 18px',
        color: t.text,
      }}>
        <div style={{ display: 'flex', gap: 14, alignItems: 'flex-start', marginBottom: 16 }}>
          <SmallUsbIcon dark={dark} size={40} />
          <div style={{ flex: 1, paddingTop: 2 }}>
            <div style={{ fontSize: 14, fontWeight: 600 }}>Unlock “Kingston DataTraveler”</div>
            <div style={{ fontSize: 12, color: t.textDim, marginTop: 2 }}>
              Choose how to authenticate this BitLocker volume.
            </div>
          </div>
        </div>

        <Segmented dark={dark} options={['Password', 'Recovery key', 'BEK file']} value={method} />

        <div style={{ marginTop: 14 }}>
          {method === 'Password' && (
            <>
              <div style={{ fontSize: 12, fontWeight: 500, marginBottom: 6 }}>Password</div>
              <Field dark={dark} value="••••••••••••" mask focused />
            </>
          )}
          {method === 'Recovery key' && (
            <>
              <div style={{ fontSize: 12, fontWeight: 500, marginBottom: 6 }}>Recovery key</div>
              <Field dark={dark} mono focused value="482915-700324-118867-294005-637012-841559-902117-555638" />
              <div style={{ fontSize: 11, color: t.textFaint, marginTop: 6 }}>
                48 digits in 8 groups of 6 · auto-formatted as you type
              </div>
            </>
          )}
          {method === 'BEK file' && (
            <>
              <div style={{ fontSize: 12, fontWeight: 500, marginBottom: 6 }}>Key file</div>
              <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
                <Button dark={dark} variant="secondary">Choose file…</Button>
                <span style={{ fontFamily: SFMONO, fontSize: 12, color: t.textDim }}>
                  Backup.BEK
                </span>
              </div>
            </>
          )}
        </div>

        <div style={{ marginTop: 16, borderTop: `0.5px solid ${t.divider}`, paddingTop: 12 }}>
          <Checkbox dark={dark} checked={true} label="Remember for this session" />
        </div>

        <div style={{ marginTop: 16, display: 'flex', justifyContent: 'flex-end', gap: 8 }}>
          <Button dark={dark} variant="secondary">Cancel</Button>
          <Button dark={dark} variant="primary">Unlock</Button>
        </div>
      </div>
    </div>
  );
}

function ScreenSheet({ dark, method }) {
  // Screen 2 underneath, sheet on top.
  return (
    <div style={{ height: '100%', position: 'relative' }}>
      <ScreenDetected dark={dark} />
      <UnlockSheet dark={dark} method={method} />
    </div>
  );
}

// ─── 4. DECRYPTING ────────────────────────────────────────────────────
function ProgressBar({ dark, value }) {
  const t = TOKENS[dark ? 'dark' : 'light'];
  return (
    <div style={{
      height: 6, borderRadius: 999, background: t.progressTrack,
      overflow: 'hidden', position: 'relative',
    }}>
      <div style={{
        width: `${value * 100}%`, height: '100%',
        background: t.accent,
        borderRadius: 999,
        boxShadow: `inset 0 0.5px 0 rgba(255,255,255,0.3)`,
      }} />
    </div>
  );
}

function ScreenDecrypting({ dark }) {
  const t = TOKENS[dark ? 'dark' : 'light'];
  return (
    <div style={{ height: '100%', display: 'flex', flexDirection: 'column', padding: '36px 28px 24px' }}>
      <div style={{
        background: t.card,
        border: `0.5px solid ${t.cardBorder}`,
        borderRadius: 10, padding: 18,
        boxShadow: t.cardShadow,
        display: 'flex', gap: 14, alignItems: 'center',
      }}>
        <SmallUsbIcon dark={dark} size={44} />
        <div style={{ flex: 1 }}>
          <div style={{ fontSize: 14, fontWeight: 600 }}>Kingston DataTraveler</div>
          <div style={{ fontSize: 12, color: t.textDim, marginTop: 2 }}>Decrypting…</div>
        </div>
        <div style={{ fontSize: 22, fontWeight: 600, letterSpacing: -0.5, fontVariantNumeric: 'tabular-nums' }}>37<span style={{ fontSize: 13, color: t.textDim, fontWeight: 500 }}>%</span></div>
      </div>

      <div style={{ marginTop: 22 }}>
        <ProgressBar dark={dark} value={0.368} />
        <div style={{
          marginTop: 10, fontSize: 12, color: t.textDim,
          fontFamily: SF, fontVariantNumeric: 'tabular-nums',
          display: 'flex', justifyContent: 'space-between', gap: 8,
        }}>
          <span>47.2 GB of 128.3 GB</span>
          <span>~12 min remaining</span>
          <span>78 MB/s</span>
        </div>
      </div>

      <div style={{ flex: 1 }} />

      <div style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 11, color: t.textFaint, marginBottom: 12 }}>
        <svg width="11" height="11" viewBox="0 0 12 12" fill="none">
          <circle cx="6" cy="6" r="4.5" stroke={t.textFaint} />
          <path d="M6 4v2.5l1.5 1" stroke={t.textFaint} strokeLinecap="round" />
        </svg>
        Decrypting to <span style={{ fontFamily: SFMONO }}>/tmp/bl/decrypted.img</span>
      </div>

      <div style={{ display: 'flex', justifyContent: 'flex-end' }}>
        <Button dark={dark} variant="secondary">Cancel</Button>
      </div>
    </div>
  );
}

// ─── 5. MOUNTED ───────────────────────────────────────────────────────
function ScreenMounted({ dark }) {
  const t = TOKENS[dark ? 'dark' : 'light'];
  return (
    <div style={{ height: '100%', display: 'flex', flexDirection: 'column', padding: '36px 28px 24px', textAlign: 'center' }}>
      <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
        <div style={{
          width: 76, height: 76, borderRadius: 999,
          background: t.iconBgOk,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
        }}>
          <svg width="38" height="38" viewBox="0 0 38 38" fill="none">
            <path d="M9 19.5 L16 26.5 L29 12.5" stroke={t.success} strokeWidth="3.5" strokeLinecap="round" strokeLinejoin="round" fill="none" />
          </svg>
        </div>
        <div style={{ height: 16 }} />
        <div style={{ fontSize: 19, fontWeight: 600, letterSpacing: -0.2 }}>Kingston DataTraveler</div>
        <div style={{ height: 4 }} />
        <div style={{ fontSize: 13, color: t.textDim }}>Mounted and ready</div>
        <div style={{ height: 14 }} />
        <div style={{
          fontFamily: SFMONO, fontSize: 12, color: t.text,
          background: dark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)',
          padding: '5px 10px', borderRadius: 5,
        }}>/Volumes/MY_USB</div>
      </div>

      <div style={{ flex: 1 }} />

      <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
        <Button dark={dark} variant="primary" full>Open in Finder</Button>
        <Button dark={dark} variant="secondary" full>Eject</Button>
      </div>
      <div style={{ marginTop: 12, textAlign: 'center', fontSize: 11.5 }}>
        <LinkText dark={dark}>Delete cached image (frees 128 GB)</LinkText>
      </div>
    </div>
  );
}

// ─── 6. ERROR ─────────────────────────────────────────────────────────
function ScreenError({ dark }) {
  const t = TOKENS[dark ? 'dark' : 'light'];
  return (
    <div style={{ height: '100%', display: 'flex', flexDirection: 'column', padding: '36px 28px 24px', textAlign: 'center' }}>
      <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
        <div style={{
          width: 76, height: 76, borderRadius: 999,
          background: t.iconBgErr,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
        }}>
          <svg width="38" height="38" viewBox="0 0 38 38" fill="none">
            <path d="M19 9 V22" stroke={t.error} strokeWidth="3.5" strokeLinecap="round" />
            <circle cx="19" cy="28" r="2" fill={t.error} />
          </svg>
        </div>
        <div style={{ height: 16 }} />
        <div style={{ fontSize: 19, fontWeight: 600, letterSpacing: -0.2 }}>Wrong recovery key</div>
        <div style={{ height: 6 }} />
        <div style={{ fontSize: 13, color: t.textDim, maxWidth: 360, margin: '0 auto' }}>
          The 48-digit key didn't match this volume's header. Check for transposed groups and try again.
        </div>
        <div style={{ height: 14 }} />
        <div style={{
          fontFamily: SFMONO, fontSize: 11, color: t.textFaint,
          background: dark ? 'rgba(255,255,255,0.04)' : 'rgba(0,0,0,0.04)',
          padding: '5px 10px', borderRadius: 5,
        }}>dislocker: ERR_WRONG_KEY (exit 3)</div>
      </div>

      <div style={{ flex: 1 }} />

      <div style={{ display: 'flex', justifyContent: 'center', gap: 8 }}>
        <Button dark={dark} variant="secondary">Copy error details</Button>
        <Button dark={dark} variant="primary">Try again</Button>
      </div>
    </div>
  );
}

// ─── Preferences popover (shown over the empty state as a bonus) ─────
function PrefsPopover({ dark }) {
  const t = TOKENS[dark ? 'dark' : 'light'];
  const Row = ({ label, control }) => (
    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '7px 0', gap: 12 }}>
      <div style={{ fontSize: 12, color: t.text }}>{label}</div>
      {control}
    </div>
  );
  return (
    <div style={{
      position: 'absolute', top: 44, right: 12,
      width: 280,
      background: t.sheetBg,
      borderRadius: 9,
      boxShadow: t.sheetShadow,
      padding: '12px 14px',
      color: t.text,
      zIndex: 5,
    }}>
      <div style={{ fontSize: 11, fontWeight: 600, textTransform: 'uppercase', letterSpacing: 0.6, color: t.textDim, marginBottom: 4 }}>Preferences</div>
      <Row label="Image cache" control={
        <span style={{ fontFamily: SFMONO, fontSize: 11.5, color: t.textDim }}>/tmp/bl</span>
      } />
      <div style={{ borderTop: `0.5px solid ${t.divider}` }} />
      <Row label="Default method" control={
        <div style={{
          background: t.fieldBg, border: `0.5px solid ${t.fieldBorder}`,
          borderRadius: 5, padding: '2px 8px', fontSize: 11.5,
        }}>Password ▾</div>
      } />
      <div style={{ borderTop: `0.5px solid ${t.divider}` }} />
      <Row label="Always re-decrypt" control={
        <span style={{
          width: 30, height: 18, borderRadius: 999,
          background: t.accent, position: 'relative',
          boxShadow: 'inset 0 0 0 0.5px rgba(0,0,0,0.15)',
        }}>
          <span style={{ position: 'absolute', top: 1.5, left: 14, width: 15, height: 15, borderRadius: 999, background: '#fff', boxShadow: '0 1px 2px rgba(0,0,0,0.3)' }} />
        </span>
      } />
    </div>
  );
}

// ─── Menu bar extra (status item) — separate mini mockup ────────────
function MenuBarExtra({ dark }) {
  const t = TOKENS[dark ? 'dark' : 'light'];
  const states = [
    { label: 'No drive',   icon: 'idle',    sub: '—' },
    { label: 'Locked',     icon: 'lock',    sub: 'Kingston · 128 GB' },
    { label: 'Decrypting', icon: 'spin',    sub: '37% · ~12 min' },
    { label: 'Mounted',    icon: 'check',   sub: '/Volumes/MY_USB' },
  ];
  const Icon = ({ kind }) => {
    if (kind === 'idle')  return <svg width="14" height="14" viewBox="0 0 16 16"><rect x="5" y="2" width="6" height="12" rx="1.5" fill="none" stroke={t.textDim} strokeWidth="1.2"/></svg>;
    if (kind === 'lock')  return <svg width="14" height="14" viewBox="0 0 16 16"><rect x="3.5" y="7" width="9" height="6.5" rx="1.4" fill={t.warn}/><path d="M5.5 7V5a2.5 2.5 0 015 0v2" stroke={t.warn} strokeWidth="1.4" fill="none"/></svg>;
    if (kind === 'spin')  return <svg width="14" height="14" viewBox="0 0 16 16"><circle cx="8" cy="8" r="5.5" stroke={t.accent} strokeWidth="1.4" strokeDasharray="6 22" fill="none"/></svg>;
    if (kind === 'check') return <svg width="14" height="14" viewBox="0 0 16 16"><path d="M3 8.5 L7 12 L13 4" stroke={t.success} strokeWidth="1.8" fill="none" strokeLinecap="round" strokeLinejoin="round"/></svg>;
  };
  return (
    <div style={{
      width: 280,
      background: dark ? 'rgba(40,40,42,0.95)' : 'rgba(245,245,247,0.95)',
      backdropFilter: 'saturate(180%) blur(20px)',
      borderRadius: 8,
      boxShadow: dark
        ? '0 12px 30px rgba(0,0,0,0.5), 0 0 0 0.5px rgba(255,255,255,0.10)'
        : '0 12px 30px rgba(0,0,0,0.18), 0 0 0 0.5px rgba(0,0,0,0.10)',
      padding: 6,
      fontFamily: SF, fontSize: 12, color: dark ? '#F5F5F7' : '#1D1D1F',
    }}>
      {states.map((s, i) => (
        <div key={s.label} style={{
          display: 'flex', alignItems: 'center', gap: 9,
          padding: '6px 8px',
          borderRadius: 5,
          background: i === 2 ? (dark ? 'rgba(10,132,255,0.18)' : 'rgba(0,122,255,0.12)') : 'transparent',
        }}>
          <Icon kind={s.icon} />
          <div style={{ flex: 1 }}>
            <div style={{ fontWeight: 500 }}>{s.label}</div>
            <div style={{ fontSize: 10.5, color: dark ? 'rgba(235,235,245,0.55)' : 'rgba(60,60,67,0.6)', marginTop: 1 }}>{s.sub}</div>
          </div>
          {i === 2 && <span style={{ fontSize: 10.5, color: dark ? 'rgba(235,235,245,0.55)' : 'rgba(60,60,67,0.6)' }}>active</span>}
        </div>
      ))}
      <div style={{ borderTop: `0.5px solid ${dark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.08)'}`, margin: '5px 4px' }} />
      <div style={{ padding: '6px 8px', display: 'flex', justifyContent: 'space-between', color: dark ? 'rgba(235,235,245,0.55)' : 'rgba(60,60,67,0.6)' }}>
        <span>Open BitLocker Unlock</span>
        <span>⌘O</span>
      </div>
      <div style={{ padding: '6px 8px', display: 'flex', justifyContent: 'space-between', color: dark ? 'rgba(235,235,245,0.55)' : 'rgba(60,60,67,0.6)' }}>
        <span>Quit</span>
        <span>⌘Q</span>
      </div>
    </div>
  );
}

Object.assign(window, {
  TOKENS, SF, SFMONO,
  Window, Button, LinkText,
  ScreenEmpty, ScreenDetected, ScreenSheet, ScreenDecrypting, ScreenMounted, ScreenError,
  PrefsPopover, MenuBarExtra,
});
