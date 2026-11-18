import { useState, useEffect } from 'react';
import './index.css';

function App() {
  const [token, setToken] = useState(() => localStorage.getItem('interra_admin_token') || '');
  const [authError, setAuthError] = useState('');
  const [isLogged, setIsLogged] = useState(false);
  const [activeTab, setActiveTab] = useState('broadcast'); // 'broadcast' | 'audience' | 'logs'

  // Data
  const [stats, setStats] = useState(null);
  const [scheduled, setScheduled] = useState([]);
  const [devices, setDevices] = useState({ items: [], total: 0 });
  const [deviceSearch, setDeviceSearch] = useState('');
  const [isDevicesLoading, setIsDevicesLoading] = useState(false);
  const [broadcasts, setBroadcasts] = useState([]);
  const [isBroadcastsLoading, setIsBroadcastsLoading] = useState(false);

  // Form
  const [form, setForm] = useState({
    type: 'all',
    targetValue: '',
    title: '',
    body: '',
    image: '',
    link: '',
    sendAt: '',
  });
  const [sendResult, setSendResult] = useState({ text: '', ok: false });
  const [isSending, setIsSending] = useState(false);

  const api = async (path, opts = {}) => {
    const res = await fetch(path, {
      ...opts,
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer ' + token,
        ...(opts.headers || {}),
      },
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(data.error || 'Ошибка ' + res.status);
    return data;
  };

  const login = async (customToken) => {
    const t = customToken ?? token;
    setAuthError('');
    try {
      const s = await api('/api/admin/stats', { headers: { Authorization: 'Bearer ' + t } });
      setStats(s);
      setIsLogged(true);
      localStorage.setItem('interra_admin_token', t);
      fetchScheduled(t);
    } catch (e) {
      setAuthError(e.message);
    }
  };

  useEffect(() => {
    const saved = localStorage.getItem('interra_admin_token');
    if (saved) login(saved);
  }, []);

  const logout = () => {
    localStorage.removeItem('interra_admin_token');
    setToken('');
    setIsLogged(false);
  };

  const fetchStats = async () => {
    try {
      const s = await api('/api/admin/stats');
      setStats(s);
    } catch (_) {}
  };

  const fetchScheduled = async (t = token) => {
    try {
      const data = await api('/api/admin/scheduled', { headers: { Authorization: 'Bearer ' + t } });
      setScheduled(data.scheduled || []);
    } catch (_) {}
  };

  const fetchDevices = async (search = deviceSearch) => {
    setIsDevicesLoading(true);
    try {
      const q = search ? `?search=${encodeURIComponent(search)}` : '';
      const data = await api(`/api/admin/devices${q}`);
      setDevices(data);
    } catch (e) {
      console.error(e);
    } finally {
      setIsDevicesLoading(false);
    }
  };

  const fetchBroadcasts = async () => {
    setIsBroadcastsLoading(true);
    try {
      const data = await api('/api/admin/broadcasts');
      setBroadcasts(data.items || []);
    } catch (e) {
      console.error(e);
    } finally {
      setIsBroadcastsLoading(false);
    }
  };

  const cancelScheduled = async (id) => {
    try {
      await api('/api/admin/scheduled/' + id + '/cancel', { method: 'POST' });
      fetchScheduled();
    } catch (e) {
      alert(e.message);
    }
  };

  const sendPush = async () => {
    if (
      form.type === 'all' &&
      !window.confirm(`Отправить уведомление ВСЕМ пользователям (${stats?.devices?.total || 0})?\n\nЗаголовок: ${form.title}`)
    ) {
      return;
    }
    setIsSending(true);
    setSendResult({ text: '', ok: false });

    const payload = {
      title: form.title,
      body: form.body,
      target: { type: form.type, value: form.type !== 'all' ? form.targetValue : undefined },
      imageUrl: form.image || undefined,
      link: form.link || undefined,
      sendAt: form.sendAt || undefined,
    };

    try {
      const r = await api('/api/admin/broadcast', { method: 'POST', body: JSON.stringify(payload) });
      if (r.scheduled) {
        setSendResult({ text: `Отправка запланирована на ${new Date(r.sendAt).toLocaleString('ru-RU')}`, ok: true });
        fetchScheduled();
      } else {
        setSendResult({
          text: `Успешно отправлено: ${r.successCount} из ${r.recipients}${r.failureCount ? ' (ошибок: ' + r.failureCount + ')' : ''}`,
          ok: true,
        });
        fetchStats();
      }
      setForm({ ...form, title: '', body: '', image: '', link: '', sendAt: '' });
    } catch (e) {
      setSendResult({ text: e.message, ok: false });
    } finally {
      setIsSending(false);
    }
  };

  const targetDevice = (login) => {
    if (!login) return;
    setForm((f) => ({ ...f, type: 'login', targetValue: login }));
    setActiveTab('broadcast');
    window.scrollTo({ top: 0, behavior: 'smooth' });
  };

  const repeatBroadcast = (b) => {
    setForm((f) => ({
      ...f,
      type: b.target_type || 'all',
      targetValue: b.target_value || '',
      title: b.title || '',
      body: b.body || '',
    }));
    setActiveTab('broadcast');
    window.scrollTo({ top: 0, behavior: 'smooth' });
  };

  // Авторизация
  if (!isLogged) {
    return (
      <div style={{ minHeight: '100vh', display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 20 }}>
        <div style={{ maxWidth: 360, width: '100%' }}>
          <div style={{ marginBottom: 16, fontSize: 16, fontWeight: 600 }}>Интерра · Панель рассылок</div>
          <div className="panel" style={{ margin: 0 }}>
            <div className="field">
              <label className="field-label">Токен администратора</label>
              <input
                type="password"
                className="font-mono"
                placeholder="ADMIN_TOKEN"
                value={token}
                onChange={(e) => setToken(e.target.value)}
                onKeyDown={(e) => e.key === 'Enter' && login()}
                autoFocus
              />
            </div>
            <button className="btn" onClick={() => login()} style={{ width: '100%', marginTop: 8 }}>
              Войти
            </button>
            {authError && <div className="msg-alert error">{authError}</div>}
          </div>
        </div>
      </div>
    );
  }

  return (
    <div>
      <header className="app-header">
        <div className="app-title">
          <span>Интерра</span>
          <span className="app-title-tag">/ push-сервер</span>
        </div>

        <nav className="tabs-nav">
          <button
            className={`tab-link ${activeTab === 'broadcast' ? 'active' : ''}`}
            onClick={() => setActiveTab('broadcast')}
          >
            Рассылка
          </button>
          <button
            className={`tab-link ${activeTab === 'audience' ? 'active' : ''}`}
            onClick={() => {
              setActiveTab('audience');
              fetchDevices();
            }}
          >
            Устройства ({stats?.devices?.total || 0})
          </button>
          <button
            className={`tab-link ${activeTab === 'logs' ? 'active' : ''}`}
            onClick={() => {
              setActiveTab('logs');
              fetchBroadcasts();
            }}
          >
            История
          </button>
        </nav>

        <div className="header-actions">
          <div className="status-indicator">
            <span className={`status-dot ${stats?.fcmEnabled ? 'online' : ''}`}></span>
            <span>{stats?.fcmEnabled ? 'FCM активен' : 'Тестовый режим'}</span>
          </div>
          <button className="btn btn-secondary btn-sm" onClick={logout}>
            Выйти
          </button>
        </div>
      </header>

      {/* Вкладка 1: Рассылка */}
      {activeTab === 'broadcast' && (
        <main className="page-container grid-two-col">
          <section>
            <div className="panel">
              <div className="panel-title">Новое push-уведомление</div>

              <div className="field-row">
                <div className="field">
                  <label className="field-label">Кому отправить</label>
                  <select value={form.type} onChange={(e) => setForm({ ...form, type: e.target.value })}>
                    <option value="all">Всем устройствам ({stats?.devices?.total || 0})</option>
                    <option value="login">По номеру телефона / логину</option>
                    <option value="segment">По сегменту</option>
                  </select>
                </div>

                {form.type !== 'all' && (
                  <div className="field">
                    <label className="field-label">
                      {form.type === 'login' ? 'Номер телефона (7922...)' : 'Сегмент (finance, outages)'}
                    </label>
                    <input
                      type="text"
                      className="font-mono"
                      placeholder={form.type === 'login' ? '79220000000' : 'outages'}
                      value={form.targetValue}
                      onChange={(e) => setForm({ ...form, targetValue: e.target.value })}
                    />
                  </div>
                )}
              </div>

              <div className="field">
                <label className="field-label">Заголовок</label>
                <input
                  type="text"
                  placeholder="Заголовок пуша..."
                  value={form.title}
                  onChange={(e) => setForm({ ...form, title: e.target.value })}
                />
              </div>

              <div className="field">
                <label className="field-label">Текст сообщения</label>
                <textarea
                  placeholder="Текст уведомления..."
                  value={form.body}
                  onChange={(e) => setForm({ ...form, body: e.target.value })}
                />
              </div>

              <div className="field-row">
                <div className="field">
                  <label className="field-label">Картинка (URL, необязательно)</label>
                  <input
                    type="url"
                    className="font-mono"
                    placeholder="https://..."
                    value={form.image}
                    onChange={(e) => setForm({ ...form, image: e.target.value })}
                  />
                </div>
                <div className="field">
                  <label className="field-label">Ссылка при открытии (URL, необязательно)</label>
                  <input
                    type="url"
                    className="font-mono"
                    placeholder="https://..."
                    value={form.link}
                    onChange={(e) => setForm({ ...form, link: e.target.value })}
                  />
                </div>
              </div>

              <div className="field" style={{ maxWidth: 260 }}>
                <label className="field-label">Запланировать на время (необязательно)</label>
                <input
                  type="datetime-local"
                  className="font-mono"
                  value={form.sendAt}
                  onChange={(e) => setForm({ ...form, sendAt: e.target.value })}
                />
              </div>

              <div style={{ marginTop: 16 }}>
                <button className="btn" disabled={isSending} onClick={sendPush}>
                  {isSending ? 'Отправка...' : 'Отправить'}
                </button>
              </div>

              {sendResult.text && (
                <div className={`msg-alert ${sendResult.ok ? 'success' : 'error'}`}>
                  {sendResult.text}
                </div>
              )}
            </div>
          </section>

          <aside>
            <div className="panel">
              <div className="panel-title">Статистика</div>
              <div>
                <div className="stat-row">
                  <span className="stat-row-label">Всего устройств</span>
                  <span className="stat-row-val">{stats?.devices?.total || 0}</span>
                </div>
                <div className="stat-row">
                  <span className="stat-row-label">Авторизовано</span>
                  <span className="stat-row-val">{stats?.devices?.withLogin || 0}</span>
                </div>
                <div className="stat-row">
                  <span className="stat-row-label">Отправлено пушей</span>
                  <span className="stat-row-val">{stats?.totals?.success || 0}</span>
                </div>
                <div className="stat-row">
                  <span className="stat-row-label">Открытий (CTR)</span>
                  <span className="stat-row-val">
                    {stats?.totals?.success
                      ? Math.round(((stats?.totals?.opens || 0) / stats.totals.success) * 100)
                      : 0}
                    %
                  </span>
                </div>
              </div>
            </div>

            <div className="panel">
              <div className="panel-title">
                <span>Очередь отложенных</span>
                <span className="flat-tag">{scheduled.length}</span>
              </div>

              {scheduled.length === 0 ? (
                <div style={{ color: 'var(--text-dim)', fontSize: 12 }}>Очередь пуста</div>
              ) : (
                <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
                  {scheduled.map((s) => (
                    <div
                      key={s.id}
                      style={{
                        display: 'flex',
                        justifyContent: 'space-between',
                        alignItems: 'center',
                        paddingBottom: 8,
                        borderBottom: '1px solid var(--border-muted)',
                      }}
                    >
                      <div>
                        <div style={{ fontWeight: 500, fontSize: 12 }}>{s.title}</div>
                        <div className="font-mono" style={{ fontSize: 11, color: 'var(--text-dim)' }}>
                          {new Date(s.send_at).toLocaleString('ru-RU')}
                        </div>
                      </div>
                      <button className="btn btn-danger btn-sm" onClick={() => cancelScheduled(s.id)}>
                        Удалить
                      </button>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </aside>
        </main>
      )}

      {/* Вкладка 2: Устройства */}
      {activeTab === 'audience' && (
        <main className="page-container">
          <div className="panel">
            <div className="panel-title">
              <span>Список устройств</span>
              <div style={{ display: 'flex', gap: 8 }}>
                <input
                  type="text"
                  placeholder="Поиск по телефону или платформе..."
                  value={deviceSearch}
                  onChange={(e) => setDeviceSearch(e.target.value)}
                  onKeyDown={(e) => e.key === 'Enter' && fetchDevices(deviceSearch)}
                  style={{ width: 260 }}
                />
                <button
                  className="btn btn-secondary btn-sm"
                  onClick={() => fetchDevices(deviceSearch)}
                  disabled={isDevicesLoading}
                >
                  {isDevicesLoading ? '...' : 'Поиск'}
                </button>
              </div>
            </div>

            {devices.items.length === 0 ? (
              <div style={{ color: 'var(--text-dim)', padding: '24px 0', textAlign: 'center' }}>
                {isDevicesLoading ? 'Загрузка...' : 'Устройств не найдено.'}
              </div>
            ) : (
              <table className="pure-table">
                <thead>
                  <tr>
                    <th style={{ width: 50 }}>#</th>
                    <th>Телефон / логин</th>
                    <th>Платформа</th>
                    <th>Версия</th>
                    <th>Дата активности</th>
                    <th style={{ textAlign: 'right' }}>Действие</th>
                  </tr>
                </thead>
                <tbody>
                  {devices.items.map((d) => (
                    <tr key={d.id}>
                      <td className="font-mono" style={{ color: 'var(--text-dim)' }}>
                        {d.id}
                      </td>
                      <td>
                        {d.client_login ? (
                          <span className="font-mono" style={{ fontWeight: 600 }}>
                            +{d.client_login}
                          </span>
                        ) : (
                          <span style={{ color: 'var(--text-dim)' }}>—</span>
                        )}
                      </td>
                      <td>
                        <span className="flat-tag">{d.platform || 'android'}</span>
                      </td>
                      <td className="font-mono">{d.app_version || '1.0.2'}</td>
                      <td className="font-mono" style={{ color: 'var(--text-muted)' }}>
                        {new Date(d.updated_at).toLocaleString('ru-RU')}
                      </td>
                      <td style={{ textAlign: 'right' }}>
                        {d.client_login ? (
                          <button className="btn btn-secondary btn-sm" onClick={() => targetDevice(d.client_login)}>
                            Написать
                          </button>
                        ) : (
                          <span style={{ color: 'var(--text-dim)' }}>—</span>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>
        </main>
      )}

      {/* Вкладка 3: История */}
      {activeTab === 'logs' && (
        <main className="page-container">
          <div className="panel">
            <div className="panel-title">
              <span>История рассылок</span>
              <button
                className="btn btn-secondary btn-sm"
                onClick={fetchBroadcasts}
                disabled={isBroadcastsLoading}
              >
                {isBroadcastsLoading ? '...' : 'Обновить'}
              </button>
            </div>

            {broadcasts.length === 0 ? (
              <div style={{ color: 'var(--text-dim)', padding: '24px 0', textAlign: 'center' }}>
                {isBroadcastsLoading ? 'Загрузка...' : 'Рассылок ещё не было.'}
              </div>
            ) : (
              <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
                {broadcasts.map((b) => {
                  const ctr = b.success_count > 0 ? Math.round(((b.opens || 0) / b.success_count) * 100) : 0;
                  return (
                    <div
                      key={b.id}
                      style={{
                        padding: 12,
                        background: 'var(--bg-page)',
                        border: '1px solid var(--border-muted)',
                        borderRadius: 4,
                      }}
                    >
                      <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 4 }}>
                        <div style={{ fontWeight: 600, fontSize: 13 }}>{b.title}</div>
                        <button className="btn btn-secondary btn-sm" onClick={() => repeatBroadcast(b)}>
                          Повторить
                        </button>
                      </div>

                      <div style={{ color: 'var(--text-muted)', fontSize: 12, marginBottom: 8, whiteSpace: 'pre-wrap' }}>
                        {b.body}
                      </div>

                      <div
                        className="font-mono"
                        style={{
                          display: 'flex',
                          gap: 16,
                          fontSize: 11,
                          color: 'var(--text-dim)',
                          borderTop: '1px solid var(--border-muted)',
                          paddingTop: 6,
                          flexWrap: 'wrap',
                        }}
                      >
                        <span>Дата: {new Date(b.created_at).toLocaleString('ru-RU')}</span>
                        <span>
                          Таргет:{' '}
                          {b.target_type === 'all'
                            ? 'Все'
                            : b.target_type === 'login'
                            ? `Логин ${b.target_value}`
                            : `Сегмент ${b.target_value}`}
                        </span>
                        <span>Получателей: {b.recipients}</span>
                        <span>Доставлено: {b.success_count}</span>
                        {b.failure_count > 0 && <span style={{ color: 'var(--danger)' }}>Ошибок: {b.failure_count}</span>}
                        <span>Открыто: {b.opens || 0} ({ctr}%)</span>
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </div>
        </main>
      )}
    </div>
  );
}

export default App;
