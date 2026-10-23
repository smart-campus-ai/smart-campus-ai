import { useEffect, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Bot, SendHorizontal, User } from 'lucide-react'
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
  const scrollRef = useRef<HTMLDivElement>(null)
  const bottomRef = useRef<HTMLDivElement>(null)

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

  // Keep the latest message in view without growing the layout.
  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [messages, sendMessage.isPending])

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
          setSuggestion(res.answered ? null : (res.ticketSuggestion ?? { title: message }))
        },
      },
    )
  }

  // US10-AC2 — open the ticket form prefilled with the assistant's suggestion.
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
    // Full-bleed route (AppLayout drops the padded wrapper on /chat): fill width + height.
    <section className="flex min-h-0 flex-1 flex-col">
      <header className="flex items-center gap-3 border-b px-4 py-3">
        <span className="flex size-9 items-center justify-center rounded-full bg-primary/10 text-primary">
          <Bot className="size-5" />
        </span>
        <div>
          <h1 className="font-semibold leading-tight">Assistant du campus</h1>
          <p className="text-xs text-muted-foreground">
            Réponses issues de la base de connaissances du campus.
          </p>
        </div>
      </header>

      {/* Fixed-height scroll area: grows with the viewport, not with the message count. */}
      <div
        ref={scrollRef}
        aria-live="polite"
        aria-label="Conversation"
        role="log"
        className="min-h-0 flex-1 overflow-y-auto px-4 py-6"
      >
        <div className="mx-auto flex max-w-3xl flex-col gap-4">
          {messages.length === 0 && (
            <div className="flex flex-col items-center gap-2 py-16 text-center text-muted-foreground">
              <Bot className="size-10 opacity-40" />
              <p className="text-sm">
                Posez une question sur les services, procédures ou installations du campus.
              </p>
            </div>
          )}

          {messages.map((m) => {
            const isUser = m.role === 'user'
            return (
              <div
                key={m.id}
                className={cn('flex items-end gap-2', isUser ? 'flex-row-reverse' : 'flex-row')}
              >
                <span
                  className={cn(
                    'flex size-7 shrink-0 items-center justify-center rounded-full',
                    isUser ? 'bg-primary text-primary-foreground' : 'bg-muted text-foreground',
                  )}
                  aria-hidden
                >
                  {isUser ? <User className="size-4" /> : <Bot className="size-4" />}
                </span>
                <div
                  className={cn(
                    'max-w-[80%] rounded-2xl px-3.5 py-2 text-sm shadow-sm',
                    isUser
                      ? 'rounded-br-sm bg-primary text-primary-foreground'
                      : 'rounded-bl-sm bg-card ring-1 ring-border',
                  )}
                >
                  <p className="whitespace-pre-wrap">{m.content}</p>
                  {m.sources && m.sources.length > 0 && (
                    <p className="mt-1.5 border-t border-border/40 pt-1.5 text-xs opacity-80">
                      Sources : {m.sources.map((s) => s.title).join(', ')}
                    </p>
                  )}
                </div>
              </div>
            )
          })}

          {sendMessage.isPending && (
            <div className="flex items-end gap-2">
              <span className="flex size-7 shrink-0 items-center justify-center rounded-full bg-muted">
                <Bot className="size-4" />
              </span>
              <div className="rounded-2xl rounded-bl-sm bg-card px-3.5 py-2.5 ring-1 ring-border">
                <span className="flex gap-1" aria-label="L'assistant rédige une réponse">
                  <span className="size-1.5 animate-bounce rounded-full bg-muted-foreground [animation-delay:-0.3s]" />
                  <span className="size-1.5 animate-bounce rounded-full bg-muted-foreground [animation-delay:-0.15s]" />
                  <span className="size-1.5 animate-bounce rounded-full bg-muted-foreground" />
                </span>
              </div>
            </div>
          )}
          <div ref={bottomRef} />
        </div>
      </div>

      {/* Composer pinned at the bottom. */}
      <div className="border-t bg-background/80 px-4 py-3 backdrop-blur">
        <div className="mx-auto flex max-w-3xl flex-col gap-2">
          {showEscalation && (
            <div className="flex items-center justify-between gap-3 rounded-lg bg-accent/10 px-3 py-2 text-sm">
              <span className="text-muted-foreground">
                L'assistant n'a pas pu répondre. Vous pouvez créer un ticket de support.
              </span>
              <Button size="sm" onClick={escalate}>
                Créer un ticket
              </Button>
            </div>
          )}
          <form className="flex items-center gap-2" onSubmit={onSubmit} aria-label="Envoyer un message">
            <label htmlFor="chat-input" className="sr-only">
              Votre message
            </label>
            <Input
              id="chat-input"
              className="h-10 flex-1"
              value={input}
              onChange={(e) => setInput(e.target.value)}
              placeholder="Écrivez votre message…"
              autoComplete="off"
            />
            <Button
              type="submit"
              size="icon"
              className="size-10"
              disabled={sendMessage.isPending || !input.trim()}
              aria-label="Envoyer"
            >
              <SendHorizontal className="size-4" />
            </Button>
            {!showEscalation && (
              <Button type="button" variant="outline" className="h-10" onClick={escalate}>
                Créer un ticket
              </Button>
            )}
          </form>
        </div>
      </div>
    </section>
  )
}
