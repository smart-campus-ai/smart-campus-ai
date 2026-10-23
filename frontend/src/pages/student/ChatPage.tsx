import { useEffect, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Bot, SendHorizontal, Sparkles, User } from 'lucide-react'
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

const SUGGESTIONS = [
  'Comment réserver une salle de travail ?',
  'Quels sont les horaires de la bibliothèque ?',
  'Comment me connecter au Wi-Fi du campus ?',
]

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

  const send = (raw: string) => {
    const message = raw.trim()
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

  const onSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    send(input)
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
    <section className="flex min-h-0 flex-1 flex-col bg-background">
      <header className="flex items-center gap-3 border-b border-border bg-card/60 px-6 py-4 backdrop-blur">
        <span className="bg-gradient-brand flex size-10 items-center justify-center rounded-xl text-white shadow-sm">
          <Bot className="size-5" />
        </span>
        <div>
          <h1 className="font-heading font-semibold leading-tight">Assistant du campus</h1>
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
        className="scroll-area min-h-0 flex-1 overflow-y-auto px-4 py-6"
      >
        <div className="mx-auto flex max-w-3xl flex-col gap-4">
          {messages.length === 0 && (
            <div className="flex flex-col items-center gap-5 py-12 text-center">
              <span className="bg-gradient-brand flex size-14 items-center justify-center rounded-2xl text-white shadow-md">
                <Sparkles className="size-7" />
              </span>
              <div className="space-y-1">
                <p className="font-heading text-lg font-medium">Comment puis-je vous aider ?</p>
                <p className="text-sm text-muted-foreground">
                  Posez une question sur les services, procédures ou installations du campus.
                </p>
              </div>
              <div className="flex flex-wrap justify-center gap-2 pt-2">
                {SUGGESTIONS.map((s) => (
                  <button
                    key={s}
                    type="button"
                    onClick={() => send(s)}
                    className="rounded-full border border-border bg-card px-3.5 py-1.5 text-sm text-muted-foreground shadow-card transition-colors hover:border-primary/40 hover:text-foreground"
                  >
                    {s}
                  </button>
                ))}
              </div>
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
                    'flex size-8 shrink-0 items-center justify-center rounded-full',
                    isUser
                      ? 'bg-primary text-primary-foreground'
                      : 'bg-gradient-brand text-white',
                  )}
                  aria-hidden
                >
                  {isUser ? <User className="size-4" /> : <Bot className="size-4" />}
                </span>
                <div
                  className={cn(
                    'max-w-[80%] rounded-2xl px-4 py-2.5 text-sm shadow-card',
                    isUser
                      ? 'rounded-br-md bg-primary text-primary-foreground'
                      : 'rounded-bl-md bg-card ring-1 ring-foreground/5',
                  )}
                >
                  <p className="whitespace-pre-wrap leading-relaxed">{m.content}</p>
                  {m.sources && m.sources.length > 0 && (
                    <p className="mt-2 border-t border-border/40 pt-1.5 text-xs opacity-80">
                      Sources : {m.sources.map((s) => s.title).join(', ')}
                    </p>
                  )}
                </div>
              </div>
            )
          })}

          {sendMessage.isPending && (
            <div className="flex items-end gap-2">
              <span className="bg-gradient-brand flex size-8 shrink-0 items-center justify-center rounded-full text-white">
                <Bot className="size-4" />
              </span>
              <div className="rounded-2xl rounded-bl-md bg-card px-4 py-3 shadow-card ring-1 ring-foreground/5">
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
      <div className="border-t border-border bg-card/70 px-4 py-4 backdrop-blur">
        <div className="mx-auto flex max-w-3xl flex-col gap-2">
          {showEscalation && (
            <div className="flex flex-wrap items-center justify-between gap-3 rounded-xl bg-accent/10 px-4 py-2.5 text-sm ring-1 ring-accent/20">
              <span className="text-foreground/80">
                L'assistant n'a pas pu répondre. Vous pouvez créer un ticket de support.
              </span>
              <Button size="sm" onClick={escalate}>
                Créer un ticket
              </Button>
            </div>
          )}
          <form
            className="flex items-center gap-2"
            onSubmit={onSubmit}
            aria-label="Envoyer un message"
          >
            <label htmlFor="chat-input" className="sr-only">
              Votre message
            </label>
            <Input
              id="chat-input"
              className="h-11 flex-1 rounded-xl"
              value={input}
              onChange={(e) => setInput(e.target.value)}
              placeholder="Écrivez votre message…"
              autoComplete="off"
            />
            <Button
              type="submit"
              size="icon"
              className="size-11 rounded-xl"
              disabled={sendMessage.isPending || !input.trim()}
              aria-label="Envoyer"
            >
              <SendHorizontal className="size-4" />
            </Button>
            {!showEscalation && (
              <Button type="button" variant="outline" className="h-11 rounded-xl" onClick={escalate}>
                Créer un ticket
              </Button>
            )}
          </form>
        </div>
      </div>
    </section>
  )
}
