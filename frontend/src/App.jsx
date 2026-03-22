import { useEffect, useState } from 'react';

const API_URL = import.meta.env.VITE_API_URL || 'http://localhost:4000';
const TENANT_ID = import.meta.env.VITE_TENANT_ID || '';

const headers = {
  'Content-Type': 'application/json',
  'x-tenant-id': TENANT_ID,
};

function App() {
  const [health, setHealth] = useState(null);
  const [me, setMe] = useState(null);
  const [users, setUsers] = useState([]);
  const [cycles, setCycles] = useState([]);
  const [cycleName, setCycleName] = useState('');
  const [inviteEmail, setInviteEmail] = useState('');
  const [inviteName, setInviteName] = useState('');
  const [message, setMessage] = useState('');

  useEffect(() => {
    fetch(`${API_URL}/health`, { headers })
      .then((r) => r.json())
      .then(setHealth)
      .catch(console.error);

    fetch(`${API_URL}/me`, { headers })
      .then((r) => r.json())
      .then((d) => setMe(d.user))
      .catch(console.error);

    fetch(`${API_URL}/users`, { headers })
      .then((r) => r.json())
      .then((d) => setUsers(d.users || []))
      .catch(console.error);

    fetch(`${API_URL}/review-cycles`, { headers })
      .then((r) => r.json())
      .then((d) => setCycles(d.cycles || []))
      .catch(console.error);
  }, []);

  async function createCycle(e) {
    e.preventDefault();
    const res = await fetch(`${API_URL}/review-cycles`, {
      method: 'POST',
      headers,
      body: JSON.stringify({ name: cycleName }),
    });
    const data = await res.json();
    if (data.cycle) {
      setCycles((prev) => [data.cycle, ...prev]);
      setCycleName('');
      setMessage('Review cycle created!');
    }
  }

  async function inviteUser(e) {
    e.preventDefault();
    const res = await fetch(`${API_URL}/users/invite`, {
      method: 'POST',
      headers,
      body: JSON.stringify({ email: inviteEmail, name: inviteName }),
    });
    const data = await res.json();
    if (data.user) {
      setUsers((prev) => [...prev, data.user]);
      setInviteEmail('');
      setInviteName('');
      setMessage(`Invited ${data.user.name}!`);
    }
  }

  return (
    <div style={{ fontFamily: 'system-ui', padding: '2rem', maxWidth: '900px', margin: '0 auto' }}>
      <h1>360 Review SaaS</h1>

      {health && (
        <p style={{ color: 'green' }}>
          API status: {health.status} | Tenant: {health.tenant_id}
        </p>
      )}

      {me && (
        <p>
          Logged in as: <strong>{me.name}</strong> ({me.role})
        </p>
      )}

      {message && <p style={{ color: 'blue' }}>{message}</p>}

      <hr />

      <h2>Review Cycles</h2>
      <form onSubmit={createCycle} style={{ display: 'flex', gap: '0.5rem', marginBottom: '1rem' }}>
        <input
          value={cycleName}
          onChange={(e) => setCycleName(e.target.value)}
          placeholder="Cycle name (e.g. Q2 2026 Engineering 360)"
          style={{ flex: 1, padding: '0.5rem' }}
          required
        />
        <button type="submit" style={{ padding: '0.5rem 1rem' }}>Create Cycle</button>
      </form>
      <ul>
        {cycles.map((c) => (
          <li key={c.id}>
            <strong>{c.name}</strong> — {c.status} ({c.start_date || 'no start'} → {c.end_date || 'no end'})
          </li>
        ))}
      </ul>

      <hr />

      <h2>Team Members ({users.length})</h2>
      <form onSubmit={inviteUser} style={{ display: 'flex', gap: '0.5rem', marginBottom: '1rem' }}>
        <input
          value={inviteName}
          onChange={(e) => setInviteName(e.target.value)}
          placeholder="Name"
          style={{ padding: '0.5rem' }}
          required
        />
        <input
          value={inviteEmail}
          onChange={(e) => setInviteEmail(e.target.value)}
          placeholder="Email"
          type="email"
          style={{ flex: 1, padding: '0.5rem' }}
          required
        />
        <button type="submit" style={{ padding: '0.5rem 1rem' }}>Invite</button>
      </form>
      <ul>
        {users.map((u) => (
          <li key={u.id}>{u.name} &lt;{u.email}&gt; — {u.role}</li>
        ))}
      </ul>

      <hr />
      <p style={{ color: '#888', fontSize: '0.875rem' }}>
        Next: Add auth, survey forms, rater assignments, and 360 report dashboards.
      </p>
    </div>
  );
}

export default App;
