import { Navigate, Route, Routes } from 'react-router-dom'
import { useAuth } from '@/auth/context'
import { AppLayout } from '@/app/AppLayout'
import { ProtectedRoute } from '@/app/ProtectedRoute'
import { LoginPage } from '@/pages/LoginPage'
import { ForbiddenPage } from '@/pages/ForbiddenPage'
import { MyTicketsPage } from '@/pages/student/MyTicketsPage'
import { NewTicketPage } from '@/pages/student/NewTicketPage'
import { ChatPage } from '@/pages/student/ChatPage'
import { PrivacyPage } from '@/pages/student/PrivacyPage'
import { TicketDetailPage } from '@/pages/TicketDetailPage'
import { AdminTicketsPage } from '@/pages/admin/AdminTicketsPage'
import { AdminKpiPage } from '@/pages/admin/AdminKpiPage'

function HomeRedirect() {
  const { user } = useAuth()
  if (!user) return <Navigate to="/login" replace />
  return <Navigate to={user.role === 'admin' ? '/admin/tickets' : '/tickets'} replace />
}

export default function App() {
  return (
    <Routes>
      <Route path="/login" element={<LoginPage />} />
      <Route path="/forbidden" element={<ForbiddenPage />} />

      {/* Authenticated area with the shared layout. */}
      <Route
        element={
          <ProtectedRoute>
            <AppLayout />
          </ProtectedRoute>
        }
      >
        <Route index element={<HomeRedirect />} />

        {/* Student */}
        <Route path="tickets" element={<ProtectedRoute role="student"><MyTicketsPage /></ProtectedRoute>} />
        <Route path="tickets/new" element={<ProtectedRoute role="student"><NewTicketPage /></ProtectedRoute>} />
        <Route path="chat" element={<ProtectedRoute role="student"><ChatPage /></ProtectedRoute>} />
        <Route path="privacy" element={<ProtectedRoute role="student"><PrivacyPage /></ProtectedRoute>} />

        {/* US09 — shareable deep link to a ticket (student owner view). */}
        <Route path="tickets/:ticketId" element={<TicketDetailPage />} />

        {/* Admin */}
        <Route path="admin/tickets" element={<ProtectedRoute role="admin"><AdminTicketsPage /></ProtectedRoute>} />
        <Route path="admin/tickets/:ticketId" element={<ProtectedRoute role="admin"><TicketDetailPage /></ProtectedRoute>} />
        <Route path="admin/kpi" element={<ProtectedRoute role="admin"><AdminKpiPage /></ProtectedRoute>} />
      </Route>

      <Route path="*" element={<HomeRedirect />} />
    </Routes>
  )
}
