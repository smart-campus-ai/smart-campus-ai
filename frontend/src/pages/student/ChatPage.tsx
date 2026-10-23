import { useEffect, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { cn } from 'cn'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import type { ChatMessage } from '@/domain/models'
import { useSendChatMessage } from '@/hooks/queries'

const SESSION_KEY = 'sc.chat.sessionId'
const MESSAGES_KEY = 'sc.chat.messages'

interface ChatSuggestion {
  title?: string
  description?: string
}

export function ChatPage() {
  const navigate = useNavigate()
  const sendMessage = useSendChatMessage()
  const [messages, setMessages] = useState<ChatMessage[]>([])
  const [input, setInput] = useState('')
  const [sessionId, setSessionId] = useState<string | undefined>(
    () => localStorage.getItem(SESSION_KEY) ?? undefined,
  )
  const [suggestion, setSuggestion] = useState<ChatSuggestion | null>(null)
  const liveRef = useRef<HTMLDivElement>(null)

  // US02-AC5 — restore the session transcript on reload.
  useEffect(() => {
    const stored = localStorage.getItem(MESSAGES_KEY)
    if (stored) {
      try {
        setMessages(JSON.parse(stored) as ChatMessage[])
      } catch {
        /* ignore corrupt cache */
      }
    }
  }, [])

  useEffect(() => {
    localStorage.setItem(MESSAGES_KEY, JSON.stringify(messages))
  }, [messages])

  // US10-AC1 — the escalation is highlighted when the assistant could not answer.
  const showEscalation = suggestion !== null

  const onSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    const message = input.trim()
    if (!message) return

    const userMsg: ChatMessage = {
      id: `local-${Date.now()}`,
      role: 'user',
      content: message,
      createdAt: new Date().toISOString(),
    }
    setMessages((prev) => [...prev, userMsg])
    setInput('')

    sendMessage.mutate(
      { sessionId, message },
      {
        onSuccess: (res) => {
          setSessionId(res.sessionId)
          localStorage.setItem(SESSION_KEY, res.sessionId)
          setMessages((prev) => [...prev, res.reply])
          // answered=false → keep the suggested prefill for escalation (US10).
          setSuggestion(res.answered ? null : (res.ticketSuggestion ?? { title: message }))
        },
      },
    )
  }

  // US10-AC2 — open the ticket form prefilled with the assistant's suggestion
  // (or a transcript-derived fallback).
  const escalate = () => {
    const lastUser = [...messages].reverse().find((m) => m.role === 'user')
    const fallbackTitle = lastUser ? lastUser.content.slice(0, 80) : 'Demande issue du chat'
    const fallbackDescription = messages
      .map((m) => `${m.role === 'user' ? 'Moi' : 'Assistant'} : ${m.content}`)
      .join('\n')
    navigate('/tickets/new', {
      state: {
        prefill: {
          title: suggestion?.title ?? fallbackTitle,
          description: suggestion?.description ?? fallbackDescription,
        },
      },
    })
  }

  return (
    <section className="mx-auto flex max-w-2xl flex-col gap-4">
      <h1 className="text-xl font-semibold">Assistant du campus</h1>

      <div
        ref={liveRef}
        aria-live="polite"
        aria-label="Conversation"
        role="log"
        className="flex min-h-64 flex-col gap-3 rounded-lg border bg-card p-4"
      >
        {messages.length === 0 && (
          <p className="text-sm text-muted-foreground">
            Posez une question sur les services, procédures ou installations du campus.
          </p>
        )}
        {messages.map((m) => (
          <div
            key={m.id}
            className={cn(
              'max-w-[85%] rounded-lg px-3 py-2 text-sm',
              m.role === 'user'
                ? 'self-end bg-primary text-primary-foreground'
                : 'self-start bg-muted',
            )}
          >
            <p className="whitespace-pre-wrap">{m.content}</p>
            {m.sources && m.sources.length > 0 && (
              <p className="mt-1 text-xs opacity-80">
                Sources : {m.sources.map((s) => s.title).join(', ')}
              </p>
            )}
          </div>
        ))}
        {sendMessage.isPending && (
          <p className="self-start text-sm text-muted-foreground">L'assistant rédige une réponse…</p>
        )}
      </div>

      {/* US10-AC1 — escalation button, highlighted after a "je ne sais pas". */}
      <div>
        <Button variant={showEscalation ? 'default' : 'outline'} onClick={escalate}>
          {showEscalation ? 'Créer un ticket à partir de cette conversation' : 'Créer un ticket'}
        </Button>
      </div>

      <form className="flex gap-2" onSubmit={onSubmit} aria-label="Envoyer un message">
        <label htmlFor="chat-input" className="sr-only">
          Votre message
        </label>
        <Input
          id="chat-input"
          value={input}
          onChange={(e) => setInput(e.target.value)}
          placeholder="Écrivez votre message…"
          autoComplete="off"
        />
        <Button type="submit" disabled={sendMessage.isPending || !input.trim()}>
          Envoyer
        </Button>
      </form>
    </section>
  )
}
