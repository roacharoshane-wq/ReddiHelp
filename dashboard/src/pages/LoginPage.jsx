import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAuthStore } from '../stores/authStore'
import { api } from '../api/client'
import { Zap } from 'lucide-react'
import toast from 'react-hot-toast'

export default function LoginPage() {
  const [tab, setTab] = useState('password')
  const [username, setUsername] = useState('')
  const [password, setPassword] = useState('')
  const [phone, setPhone] = useState('')
  const [otp, setOtp] = useState('')
  const [otpSent, setOtpSent] = useState(false)
  const [loading, setLoading] = useState(false)
  const navigate = useNavigate()
  const login = useAuthStore((s) => s.login)

  const handlePasswordLogin = async (e) => {
    e.preventDefault()
    setLoading(true)
    try {
      const res = await api.post('/auth/login', { username, password })
      login(res)
      navigate('/dashboard')
    } catch (err) {
      toast.error(err.message)
    } finally {
      setLoading(false)
    }
  }

  const handleRequestOtp = async () => {
    setLoading(true)
    try {
      await api.post('/auth/request-otp', { phone })
      setOtpSent(true)
      toast.success('OTP sent')
    } catch (err) {
      toast.error(err.message)
    } finally {
      setLoading(false)
    }
  }

  const handleOtpLogin = async (e) => {
    e.preventDefault()
    setLoading(true)
    try {
      const res = await api.post('/auth/verify-otp', { phone, otp, role: 'coordinator' })
      login(res)
      navigate('/dashboard')
    } catch (err) {
      toast.error(err.message)
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50 dark:bg-gray-900 p-4">
      <div className="w-full max-w-sm">
        <div className="text-center mb-8">
          <Zap className="w-10 h-10 text-teal-500 mx-auto mb-2" />
          <h1 className="text-2xl font-bold text-gray-900 dark:text-white">ReddiHelp</h1>
          <p className="text-sm text-gray-500 dark:text-gray-400">Coordinator Dashboard</p>
        </div>

        <div className="bg-white dark:bg-gray-800 rounded-xl shadow-lg p-6">
          <div className="flex mb-6 bg-gray-100 dark:bg-gray-700 rounded-lg p-1">
            {['password', 'otp'].map((t) => (
              <button
                key={t}
                onClick={() => setTab(t)}
                className={`flex-1 py-1.5 text-xs font-medium rounded-md transition-colors ${tab === t ? 'bg-white dark:bg-gray-600 shadow-sm' : 'text-gray-500'}`}
              >
                {t === 'password' ? 'Username' : 'Phone OTP'}
              </button>
            ))}
          </div>

          {tab === 'password' ? (
            <form onSubmit={handlePasswordLogin} className="space-y-4">
              <input value={username} onChange={(e) => setUsername(e.target.value)} placeholder="Username" className="w-full px-3 py-2.5 border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-700 text-sm" />
              <input value={password} onChange={(e) => setPassword(e.target.value)} type="password" placeholder="Password" className="w-full px-3 py-2.5 border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-700 text-sm" />
              <button disabled={loading} className="w-full py-2.5 bg-teal-600 hover:bg-teal-700 text-white font-medium rounded-lg text-sm disabled:opacity-50">
                {loading ? 'Signing in...' : 'Sign In'}
              </button>
            </form>
          ) : (
            <form onSubmit={handleOtpLogin} className="space-y-4">
              <input value={phone} onChange={(e) => setPhone(e.target.value)} placeholder="+1876..." className="w-full px-3 py-2.5 border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-700 text-sm" />
              {!otpSent ? (
                <button type="button" onClick={handleRequestOtp} disabled={loading} className="w-full py-2.5 bg-teal-600 hover:bg-teal-700 text-white font-medium rounded-lg text-sm disabled:opacity-50">
                  {loading ? 'Sending...' : 'Send OTP'}
                </button>
              ) : (
                <>
                  <input value={otp} onChange={(e) => setOtp(e.target.value)} placeholder="6-digit OTP" maxLength={6} className="w-full px-3 py-2.5 border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-700 text-sm text-center tracking-widest" />
                  <button disabled={loading} className="w-full py-2.5 bg-teal-600 hover:bg-teal-700 text-white font-medium rounded-lg text-sm disabled:opacity-50">
                    {loading ? 'Verifying...' : 'Verify & Sign In'}
                  </button>
                </>
              )}
            </form>
          )}
        </div>
      </div>
    </div>
  )
}
