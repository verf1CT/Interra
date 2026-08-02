import { useState, useEffect } from 'react';
import './index.css';

function App() {
  const [token, setToken] = useState('');
  const [authError, setAuthError] = useState('');
  const [isLogged, setIsLogged] = useState(false);
  const [stats, setStats] = useState(null);
  const [scheduled, setScheduled] = useState([]);
  const [form, setForm] = useState({ type: 'all', targetValue: '', title: '', body: '', image: '', link: '', sendAt: '' });
  const [sendResult, setSendResult] = useState({ text: '', ok: false });
  const [isSending, setIsSending] = useState(false);

  const api = async (path, opts = {}) => {
    const res = await fetch(path, {
      ...opts,
      headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + token, ...(opts.headers || {}) },
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(data.error || ('HTTP ' + res.status));
    return data;
  };

  const login = async () => {
    setAuthError('');
    try {
      await fetchStats(token);
      setIsLogged(true);
      fetchScheduled(token);
    } catch (e) {
      setAuthError(e.message);
    }
  };

  const fetchStats = async (t = token) => {
    const s = await api('/api/admin/stats', { headers: { Authorization: 'Bearer ' + t } });
    setStats(s);
  };

  const fetchScheduled = async (t = token) => {
    const data = await api('/api/admin/scheduled', { headers: { Authorization: 'Bearer ' + t } });
    setScheduled(data.scheduled || []);
  };

  const cancelScheduled = async (id) => {
    try {
      await api('/api/admin/scheduled/' + id + '/cancel', { method: 'POST' });
      fetchScheduled();
    } catch (e) { alert(e.message); }
  };

  const sendPush = async () => {
    if (form.type === 'all' && !window.confirm(`Отправить пуш ВСЕМ клиентам?\n\nЗаголовок: ${form.title}`)) return;
    setIsSending(true);
    setSendResult({ text: '', ok: false });
    
    const payload = {
      title: form.title,
      body: form.body,
      target: { type: form.type, value: form.type !== 'all' ? form.targetValue : undefined },
      imageUrl: form.image || undefined,
      link: form.link || undefined,
      sendAt: form.sendAt || undefined
    };

    try {
      const r = await api('/api/admin/broadcast', { method: 'POST', body: JSON.stringify(payload) });
      if (r.scheduled) {
        setSendResult({ text: `Запланировано на ${new Date(r.sendAt).toLocaleString()}`, ok: true });
        fetchScheduled();
      } else {
        setSendResult({ text: `Отправлено: ${r.successCount}/${r.recipients}${r.failureCount ? ', ошибок: ' + r.failureCount : ''}`, ok: true });
        fetchStats();
      }
      setForm({ ...form, title: '', body: '', image: '', link: '', sendAt: '' });
    } catch (e) {
      setSendResult({ text: e.message, ok: false });
    } finally {
      setIsSending(false);
    }
  };

  if (!isLogged) {
    return (
      <div style={{ display: 'flex', flexDirection: 'column', minHeight: '100vh' }}>
        <header className="top-nav">
          <div className="wordmark">
            <div style={{ width: 32, height: 32, background: 'var(--color-signal-lime)', borderRadius: 4, display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#000', fontSize: 24, boxShadow: 'var(--shadow-sm)'}}>I</div>
            ИНТЕРРА ПРОТОКОЛ
          </div>
        </header>
        <main className="layout-container" style={{ display: 'flex', flex: 1, alignItems: 'center', justifyContent: 'center', padding: '120px 24px' }}>
          <div style={{ maxWidth: 480, width: '100%', textAlign: 'center' }}>
            <div className="metadata-label bracketed" style={{ marginBottom: 24 }}>ДЛЯ АГЕНТОВ · ШЛЮЗ АДМИНА</div>
            <h1 className="display-title" style={{ marginBottom: 40 }}>Доступ к <i>Протоколу.</i></h1>
            
            <div className="form-group" style={{ textAlign: 'left' }}>
              <input 
                type="password" 
                className="font-mono"
                placeholder="ADMIN_TOKEN" 
                value={token} 
                onChange={e => setToken(e.target.value)}
                onKeyDown={e => e.key === 'Enter' && login()}
                style={{ textAlign: 'center', padding: '16px', letterSpacing: '0.1em' }}
              />
            </div>
            
            <button className="btn-lime" onClick={login} style={{ width: '100%', marginTop: 8 }}>
              АВТОРИЗАЦИЯ
            </button>
            
            {authError && (
              <div className="code-panel" style={{ color: 'var(--color-signal-lime)', textAlign: 'left', marginTop: 24 }}>
                <span className="kw">ОШИБКА</span>: {authError}
              </div>
            )}
          </div>
        </main>
      </div>
    );
  }

  return (
    <div style={{ paddingBottom: 120 }}>
      <header className="top-nav">
        <div className="wordmark">
          <div style={{ width: 28, height: 28, background: 'var(--color-signal-lime)', borderRadius: 4, display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#000', fontSize: 20, boxShadow: 'var(--shadow-sm)'}}>I</div>
          ИНТЕРРА
        </div>
        <div className="ghost-nav">
          <button className="ghost-btn">РАССЫЛКА</button>
          <button className="ghost-btn">АУДИТОРИЯ</button>
          <button className="ghost-btn">ЖУРНАЛЫ</button>
        </div>
        <div>
          <button className="btn-outline-lime">СИСТЕМА: {stats?.fcmEnabled ? 'АКТИВНА' : 'DRY-RUN'}</button>
        </div>
      </header>

      <div className="neon-divider"></div>

      <main className="layout-container dashboard-grid">
        <section>
          <article className="sharp-card">
            <div className="card-eyebrow">
              <span className="metadata-label">ДЛЯ ЛЮДЕЙ · ШЛЮЗ РАССЫЛОК</span>
              <span className="metadata-label">T 01</span>
            </div>
            <h2 className="card-title">Отправка Сигнала</h2>
            
            <div className="input-row">
              <div className="form-group">
                <span className="metadata-label" style={{ marginBottom: 8 }}>ЦЕЛЕВАЯ АУДИТОРИЯ</span>
                <select value={form.type} onChange={e => setForm({...form, type: e.target.value})}>
                  <option value="all">ГЛОБАЛЬНО [ВСЕМ]</option>
                  <option value="segment">СЕГМЕНТУ [ID]</option>
                  <option value="login">УЗЛУ [ЛОГИН]</option>
                </select>
              </div>
              
              {form.type !== 'all' && (
                <div className="form-group">
                  <span className="metadata-label" style={{ marginBottom: 8 }}>ИДЕНТИФИКАТОР ЦЕЛИ</span>
                  <input 
                    type="text" 
                    className="font-mono"
                    placeholder={form.type === 'login' ? 'ЛОГИН_ПОЛЬЗОВАТЕЛЯ' : 'ТЕГ_СЕГМЕНТА'} 
                    value={form.targetValue} 
                    onChange={e => setForm({...form, targetValue: e.target.value})} 
                  />
                </div>
              )}
            </div>

            <div className="form-group">
              <span className="metadata-label" style={{ marginBottom: 8 }}>ЗАГОЛОВОК СИГНАЛА</span>
              <input type="text" placeholder="Название уведомления" value={form.title} onChange={e => setForm({...form, title: e.target.value})} />
            </div>

            <div className="form-group">
              <span className="metadata-label" style={{ marginBottom: 8 }}>ТЕКСТ СИГНАЛА</span>
              <textarea placeholder="Содержимое уведомления..." value={form.body} onChange={e => setForm({...form, body: e.target.value})} />
            </div>

            <div className="input-row">
              <div className="form-group">
                <span className="metadata-label" style={{ marginBottom: 8 }}>ССЫЛКА НА АССЕТ (URL)</span>
                <input type="url" className="font-mono" placeholder="https://" value={form.image} onChange={e => setForm({...form, image: e.target.value})} />
              </div>
              <div className="form-group">
                <span className="metadata-label" style={{ marginBottom: 8 }}>DEEP LINK (ССЫЛКА)</span>
                <input type="url" className="font-mono" placeholder="https://" value={form.link} onChange={e => setForm({...form, link: e.target.value})} />
              </div>
            </div>

            <div className="form-group" style={{ marginBottom: 32 }}>
              <span className="metadata-label" style={{ marginBottom: 8 }}>ОТЛОЖИТЬ ДО (ВРЕМЯ)</span>
              <input type="datetime-local" className="font-mono" value={form.sendAt} onChange={e => setForm({...form, sendAt: e.target.value})} />
            </div>

            <button className="btn-lime" disabled={isSending} onClick={sendPush}>
              {isSending ? 'ОТПРАВКА...' : 'ОТПРАВИТЬ СИГНАЛ'}
            </button>
            
            {sendResult.text && (
              <div className="code-panel" style={{ marginTop: 24, color: sendResult.ok ? 'var(--color-signal-lime)' : 'var(--color-error)' }}>
                <span className="kw">{sendResult.ok ? 'УСПЕШНО' : 'ОШИБКА'}</span>: {sendResult.text}
              </div>
            )}
          </article>
        </section>

        <aside style={{ display: 'flex', flexDirection: 'column', gap: 'var(--spacing-24)' }}>
          <article className="sharp-card">
             <div className="card-eyebrow">
              <span className="metadata-label">СЕТЬ · ТЕЛЕМЕТРИЯ</span>
              <span className="metadata-label">T 02</span>
            </div>
            <h2 className="card-title">Статистика</h2>
            
            <div className="code-panel" style={{ marginTop: 0 }}>
              <div><span className="kw">УЗЛОВ.ВСЕГО</span>: <span className="str">{stats?.devices?.total || 0}</span></div>
              <div><span className="kw">УЗЛОВ.АВТОРИЗ</span>:  <span className="str">{stats?.devices?.withLogin || 0}</span></div>
              <div style={{ margin: '16px 0', borderBottom: '1px dashed var(--color-slate)' }}></div>
              <div><span className="kw">СИГНАЛОВ.ОТПРАВЛЕНО</span>: <span className="str">{stats?.totals?.success || 0}</span></div>
              <div><span className="kw">СИГНАЛОВ.CTR</span>:  <span className="str">{stats?.totals?.success ? Math.round(((stats?.totals?.opens||0) / stats.totals.success)*100) : 0}%</span></div>
            </div>
          </article>

          <article className="sharp-card">
            <div className="card-eyebrow">
              <span className="metadata-label">ОЧЕРЕДЬ · ОТЛОЖЕНО</span>
              <span className="metadata-label">T 03</span>
            </div>
            <h2 className="card-title">Ожидают отправки</h2>
            
            {scheduled.length === 0 ? (
              <div className="body-text" style={{ color: 'var(--color-smoke)' }}>Очередь пуста.</div>
            ) : (
              <div style={{ display: 'flex', flexDirection: 'column' }}>
                {scheduled.map(s => (
                  <div key={s.id} className="history-row">
                    <div>
                      <div className="body-text" style={{ color: 'var(--color-chalk)' }}>{s.title}</div>
                      <div className="font-mono" style={{ fontSize: 11, color: 'var(--color-ash)', marginTop: 4 }}>
                        TS: {new Date(s.send_at).toLocaleString()}
                      </div>
                    </div>
                    <button className="btn-outline-lime" style={{ padding: '6px 12px', fontSize: 11 }} onClick={() => cancelScheduled(s.id)}>
                      ОТМЕНА
                    </button>
                  </div>
                ))}
              </div>
            )}
          </article>
        </aside>
      </main>
    </div>
  );
}

export default App;
