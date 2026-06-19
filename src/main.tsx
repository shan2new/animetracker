import { Component, StrictMode, type ReactNode } from 'react'
import { createRoot } from 'react-dom/client'
import App from './App.tsx'
import './styles.css'

// Last-resort guard: a render-time throw shows a friendly fallback instead of a white screen.
class ErrorBoundary extends Component<{ children: ReactNode }, { error: Error | null }> {
  state = { error: null as Error | null }
  static getDerivedStateFromError(error: Error) {
    return { error }
  }
  render() {
    if (this.state.error) {
      return (
        <div style={{ minHeight: '100vh', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 14, padding: 24, textAlign: 'center', color: '#F5F5F7', background: '#0B0B0E', fontFamily: "'Geist',sans-serif" }}>
          <div style={{ fontSize: 30, color: '#F0A24E' }}>✦</div>
          <div style={{ fontSize: 19, fontWeight: 600 }}>Something went wrong</div>
          <div style={{ fontSize: 14, color: 'rgba(245,245,247,0.55)', maxWidth: 320, lineHeight: 1.5 }}>AniTrack hit an unexpected error. Reloading usually fixes it.</div>
          <button onClick={() => window.location.reload()} style={{ marginTop: 6, padding: '11px 22px', border: 'none', borderRadius: 12, cursor: 'pointer', fontSize: 14.5, fontWeight: 600, color: '#0B0B0E', background: '#F0A24E', fontFamily: 'inherit' }}>Reload</button>
        </div>
      )
    }
    return this.props.children
  }
}

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <ErrorBoundary>
      <App />
    </ErrorBoundary>
  </StrictMode>,
)
