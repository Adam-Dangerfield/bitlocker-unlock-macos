// app.jsx — Figma-style canvas: all 6 screens × light/dark + annotation.

function DataContract() {
  const SFMONO_ = '"SF Mono", ui-monospace, Menlo, monospace';
  const row = (label, body, ret) => (
    <div style={{ display: 'grid', gridTemplateColumns: '78px 1fr', gap: 12, padding: '10px 0', borderTop: '1px solid rgba(0,0,0,0.08)' }}>
      <div style={{
        fontFamily: SFMONO_, fontSize: 11, fontWeight: 600,
        color: '#0A5FD9', alignSelf: 'start', paddingTop: 2,
      }}>{label}</div>
      <div style={{ fontFamily: SFMONO_, fontSize: 11.5, color: '#29261b', lineHeight: 1.55, whiteSpace: 'pre-wrap' }}>
        {body}
        {ret && <div style={{ color: 'rgba(60,60,67,0.6)', marginTop: 4 }}>{ret}</div>}
      </div>
    </div>
  );
  return (
    <div style={{
      width: 360,
      background: '#FFFCEF',
      border: '1px solid rgba(0,0,0,0.10)',
      borderRadius: 10,
      padding: '18px 20px 16px',
      fontFamily: '-apple-system, BlinkMacSystemFont, sans-serif',
      color: '#29261b',
      boxShadow: '0 1px 0 rgba(0,0,0,0.04), 0 6px 24px rgba(0,0,0,0.06)',
    }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 4 }}>
        <span style={{ width: 7, height: 7, borderRadius: 999, background: '#0A5FD9' }} />
        <div style={{ fontSize: 10, fontWeight: 700, letterSpacing: 1, textTransform: 'uppercase', color: 'rgba(60,60,67,0.7)' }}>Annotation</div>
      </div>
      <div style={{ fontSize: 15, fontWeight: 600, marginBottom: 2 }}>Data contract</div>
      <div style={{ fontSize: 12, color: 'rgba(60,60,67,0.7)', marginBottom: 6 }}>
        For wiring to a backend (e.g. <span style={{ fontFamily: SFMONO_ }}>dislocker</span>). Not in the UI.
      </div>

      {row('Detect →', `[{
  device: "/dev/disk4s2",
  name: "Kingston DataTraveler",
  sizeBytes: 137438953472,
  isBitLocker: true,
  isLocked: true,
}]`)}
      {row('Unlock ←', `{
  device,
  method: "password" | "recovery" | "bek",
  secret?: string,
  filePath?: string,
}`,
        '→ stream {progress 0–1, bytesDone, bytesTotal, etaSec}\n→ final {mountPath} | {error: code, message}'
      )}
      {row('Eject ←', '{ mountPath }')}
      {row('Cleanup ←', '{ imagePath }')}

      <div style={{
        marginTop: 12, paddingTop: 10, borderTop: '1px solid rgba(0,0,0,0.08)',
        fontSize: 11, color: 'rgba(60,60,67,0.6)', lineHeight: 1.5,
      }}>
        <b style={{ color: '#29261b' }}>Out of scope:</b> accounts, multi-drive parallelism,
        settings sync, onboarding, marketing. Every screen one viewport tall.
      </div>
    </div>
  );
}

function ModeLabel({ children, dark }) {
  return (
    <div style={{
      display: 'inline-flex', alignItems: 'center', gap: 8,
      padding: '4px 10px', borderRadius: 999,
      background: dark ? '#1E1E20' : '#FFFFFF',
      color: dark ? '#F5F5F7' : '#1D1D1F',
      fontSize: 11, fontWeight: 600, letterSpacing: 0.4,
      boxShadow: '0 0 0 1px rgba(0,0,0,0.08), 0 1px 2px rgba(0,0,0,0.04)',
      fontFamily: SF,
    }}>
      <span style={{ width: 8, height: 8, borderRadius: 999, background: dark ? '#0A84FF' : '#FFCC00' }} />
      {children}
    </div>
  );
}

// Per-mode row of all 6 screens — function (not a component) so its returned
// fragment is unwrapped by DCSection's dcFlatten and the DCArtboards are
// visible to its artboard scan.
function screenRow(dark) {
  const W = 520, H = 640;
  return (
    <>
      <DCArtboard id={`${dark ? 'd' : 'l'}-1-empty`}      label="1 · Empty state"     width={W} height={H}>
        <Window dark={dark}>
          <ScreenEmpty dark={dark} />
        </Window>
      </DCArtboard>
      <DCArtboard id={`${dark ? 'd' : 'l'}-2-detected`}   label="2 · Drive detected"  width={W} height={H}>
        <Window dark={dark}>
          <ScreenDetected dark={dark} />
        </Window>
      </DCArtboard>
      <DCArtboard id={`${dark ? 'd' : 'l'}-3-sheet`}      label="3 · Unlock sheet"    width={W} height={H}>
        <Window dark={dark}>
          <ScreenSheet dark={dark} method="Recovery key" />
        </Window>
      </DCArtboard>
      <DCArtboard id={`${dark ? 'd' : 'l'}-4-decrypting`} label="4 · Decrypting"      width={W} height={H}>
        <Window dark={dark}>
          <ScreenDecrypting dark={dark} />
        </Window>
      </DCArtboard>
      <DCArtboard id={`${dark ? 'd' : 'l'}-5-mounted`}    label="5 · Mounted"         width={W} height={H}>
        <Window dark={dark}>
          <ScreenMounted dark={dark} />
        </Window>
      </DCArtboard>
      <DCArtboard id={`${dark ? 'd' : 'l'}-6-error`}      label="6 · Error"           width={W} height={H}>
        <Window dark={dark}>
          <ScreenError dark={dark} />
        </Window>
      </DCArtboard>
    </>
  );
}

function App() {
  return (
    <DesignCanvas>
      <DCSection
        id="overview"
        title="BitLocker Unlock — macOS"
        subtitle="Single-window utility for opening BitLocker-encrypted USB drives. ~520 × 640. Six screens; one viewport each.">
        <DCArtboard id="annotation" label="Data contract" width={400} height={560} style={{ background: 'transparent', boxShadow: 'none', border: 'none' }}>
          <div style={{ width: 400, padding: 20, display: 'flex', justifyContent: 'center' }}>
            <DataContract />
          </div>
        </DCArtboard>
      </DCSection>

      <DCSection
        id="light"
        title="Light mode"
        subtitle="Default macOS Light appearance. Vibrancy titlebar, system blue accent.">
        {screenRow(false)}
      </DCSection>

      <DCSection
        id="dark"
        title="Dark mode"
        subtitle="macOS Dark appearance. Same layout, denser shadows, brighter accent.">
        {screenRow(true)}
      </DCSection>

      <DCSection
        id="chrome"
        title="Global chrome"
        subtitle="Preferences popover (top-right gear) and the menu bar extra status item.">
        <DCArtboard id="prefs-light" label="Preferences · Light" width={520} height={300}>
          <div style={{
            width: 520, height: 300,
            background: 'linear-gradient(180deg,#E8E8EC 0%,#F2F2F5 100%)',
            borderRadius: 11, overflow: 'hidden', position: 'relative',
            boxShadow: '0 22px 50px rgba(0,0,0,0.10), 0 0 0 0.5px rgba(0,0,0,0.08)',
            fontFamily: SF,
          }}>
            {/* fake mini titlebar so the popover anchors visually */}
            <div style={{ height: 38, background: '#ECECEC', borderBottom: '0.5px solid rgba(0,0,0,0.15)', display: 'flex', alignItems: 'center', padding: '0 14px' }}>
              <div style={{ display: 'flex', gap: 8 }}>
                {['#FF5F57','#FEBC2E','#28C840'].map((c,i) => <span key={i} style={{ width: 12, height: 12, borderRadius: 999, background: c }} />)}
              </div>
              <div style={{ marginLeft: 'auto', width: 24, height: 24, borderRadius: 5, background: 'rgba(0,0,0,0.06)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                <svg width="13" height="13" viewBox="0 0 16 16" fill="none"><circle cx="8" cy="8" r="2.5" stroke="#1D1D1F" strokeWidth="1.2"/><path d="M8 2v2M8 12v2M2 8h2M12 8h2" stroke="#1D1D1F" strokeWidth="1.2" strokeLinecap="round"/></svg>
              </div>
            </div>
            {/* arrow tail */}
            <div style={{ position: 'absolute', top: 36, right: 19, width: 12, height: 12, background: '#F6F6F6', transform: 'rotate(45deg)', boxShadow: '-1px -1px 0 0.5px rgba(0,0,0,0.06)' }} />
            <PrefsPopover dark={false} />
          </div>
        </DCArtboard>

        <DCArtboard id="prefs-dark" label="Preferences · Dark" width={520} height={300}>
          <div style={{
            width: 520, height: 300,
            background: 'linear-gradient(180deg,#1A1A1C 0%,#222224 100%)',
            borderRadius: 11, overflow: 'hidden', position: 'relative',
            boxShadow: '0 22px 50px rgba(0,0,0,0.5), 0 0 0 0.5px rgba(255,255,255,0.08)',
            fontFamily: SF,
          }}>
            <div style={{ height: 38, background: '#2A2A2C', borderBottom: '0.5px solid rgba(255,255,255,0.10)', display: 'flex', alignItems: 'center', padding: '0 14px' }}>
              <div style={{ display: 'flex', gap: 8 }}>
                {['#FF5F57','#FEBC2E','#28C840'].map((c,i) => <span key={i} style={{ width: 12, height: 12, borderRadius: 999, background: c }} />)}
              </div>
              <div style={{ marginLeft: 'auto', width: 24, height: 24, borderRadius: 5, background: 'rgba(255,255,255,0.06)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                <svg width="13" height="13" viewBox="0 0 16 16" fill="none"><circle cx="8" cy="8" r="2.5" stroke="#F5F5F7" strokeWidth="1.2"/><path d="M8 2v2M8 12v2M2 8h2M12 8h2" stroke="#F5F5F7" strokeWidth="1.2" strokeLinecap="round"/></svg>
              </div>
            </div>
            <div style={{ position: 'absolute', top: 36, right: 19, width: 12, height: 12, background: '#2C2C2E', transform: 'rotate(45deg)', boxShadow: '-1px -1px 0 0.5px rgba(255,255,255,0.08)' }} />
            <PrefsPopover dark={true} />
          </div>
        </DCArtboard>

        <DCArtboard id="menubar-light" label="Menu bar extra · Light" width={320} height={300}>
          <div style={{
            width: 320, height: 300,
            background: 'linear-gradient(180deg,#7BAEFF 0%,#A4C7FF 100%)',
            borderRadius: 11, overflow: 'hidden', position: 'relative',
            boxShadow: '0 22px 50px rgba(0,0,0,0.10), 0 0 0 0.5px rgba(0,0,0,0.08)',
          }}>
            {/* fake menu bar at top */}
            <div style={{
              position: 'absolute', top: 0, left: 0, right: 0, height: 22,
              background: 'rgba(255,255,255,0.55)', backdropFilter: 'saturate(180%) blur(20px)',
              borderBottom: '0.5px solid rgba(0,0,0,0.12)',
              display: 'flex', alignItems: 'center', justifyContent: 'flex-end', padding: '0 8px', gap: 12,
              fontFamily: SF, fontSize: 11, fontWeight: 500, color: '#1D1D1F',
            }}>
              <svg width="14" height="14" viewBox="0 0 16 16"><rect x="3.5" y="7" width="9" height="6.5" rx="1.4" fill="#FF9500"/><path d="M5.5 7V5a2.5 2.5 0 015 0v2" stroke="#FF9500" strokeWidth="1.4" fill="none"/></svg>
              <span style={{ fontFamily: '"SF Mono", monospace', fontSize: 10.5 }}>78MB/s</span>
              <span>100%</span>
              <span>Mon 2:14 PM</span>
            </div>
            <div style={{ position: 'absolute', top: 26, right: 16 }}>
              <MenuBarExtra dark={false} />
            </div>
          </div>
        </DCArtboard>

        <DCArtboard id="menubar-dark" label="Menu bar extra · Dark" width={320} height={300}>
          <div style={{
            width: 320, height: 300,
            background: 'linear-gradient(180deg,#1E2940 0%,#2A3756 100%)',
            borderRadius: 11, overflow: 'hidden', position: 'relative',
            boxShadow: '0 22px 50px rgba(0,0,0,0.4), 0 0 0 0.5px rgba(255,255,255,0.06)',
          }}>
            <div style={{
              position: 'absolute', top: 0, left: 0, right: 0, height: 22,
              background: 'rgba(30,30,32,0.6)', backdropFilter: 'saturate(180%) blur(20px)',
              borderBottom: '0.5px solid rgba(255,255,255,0.10)',
              display: 'flex', alignItems: 'center', justifyContent: 'flex-end', padding: '0 8px', gap: 12,
              fontFamily: SF, fontSize: 11, fontWeight: 500, color: '#F5F5F7',
            }}>
              <svg width="14" height="14" viewBox="0 0 16 16"><rect x="3.5" y="7" width="9" height="6.5" rx="1.4" fill="#FF9F0A"/><path d="M5.5 7V5a2.5 2.5 0 015 0v2" stroke="#FF9F0A" strokeWidth="1.4" fill="none"/></svg>
              <span style={{ fontFamily: '"SF Mono", monospace', fontSize: 10.5 }}>78MB/s</span>
              <span>100%</span>
              <span>Mon 2:14 PM</span>
            </div>
            <div style={{ position: 'absolute', top: 26, right: 16 }}>
              <MenuBarExtra dark={true} />
            </div>
          </div>
        </DCArtboard>
      </DCSection>
    </DesignCanvas>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(<App />);
