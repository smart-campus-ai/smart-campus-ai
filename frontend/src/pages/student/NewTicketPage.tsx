import { useState } from 'react'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { useLocation, useNavigate } from 'react-router-dom'
import { toast } from 'sonner'
import { ApiError } from '@/domain/api'
import { useApi } from '@/api/context'
import { Button } from '@/components/ui/button'
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
} from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'
import {
  TICKET_CATEGORIES,
  ticketCreateSchema,
} from '@/domain/models'
import type { Ticket, TicketCreateInput } from '@/domain/models'
import { useCreateTicket } from '@/hooks/queries'

/** US10-AC2 — prefill payload passed via router state from the chat escalation. */
interface PrefillState {
  prefill?: { title?: string; description?: string }
}

const MAX_IMAGE_BYTES = 10 * 1024 * 1024
const ALLOWED_IMAGE_TYPES = ['image/jpeg', 'image/png']

export function NewTicketPage() {
  const navigate = useNavigate()
  const location = useLocation()
  const api = useApi()
  const prefill = (location.state as PrefillState | null)?.prefill
  const createTicket = useCreateTicket()

  const [imageError, setImageError] = useState<string | null>(null)
  const [imageFile, setImageFile] = useState<File | null>(null)
  const [formError, setFormError] = useState<string | null>(null)

  const {
    register,
    handleSubmit,
    formState: { errors },
  } = useForm<TicketCreateInput>({
    resolver: zodResolver(ticketCreateSchema),
    defaultValues: {
      title: prefill?.title ?? '',
      description: prefill?.description ?? '',
    },
  })

  // US04-AC6 — client-side validation of the attachment (type + size).
  const onImageChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setImageError(null)
    const file = e.target.files?.[0]
    if (!file) {
      setImageFile(null)
      return
    }
    if (!ALLOWED_IMAGE_TYPES.includes(file.type)) {
      setImageError('Seules les images JPG ou PNG sont acceptées.')
      setImageFile(null)
      e.target.value = ''
      return
    }
    if (file.size > MAX_IMAGE_BYTES) {
      setImageError('La taille maximale est de 10 Mo.')
      setImageFile(null)
      e.target.value = ''
      return
    }
    setImageFile(file)
  }

  // US04-AC6 — presigned POST to S3 (contract: POST /tickets/{id}/attachments).
  const uploadAttachment = async (ticket: Ticket, file: File) => {
    try {
      const presigned = await api.createAttachmentUpload(ticket.id, {
        filename: file.name,
        contentType: file.type as 'image/jpeg' | 'image/png',
        size: file.size,
      })
      const form = new FormData()
      for (const [key, value] of Object.entries(presigned.fields)) form.append(key, value)
      form.append('file', file)
      await fetch(presigned.url, { method: 'POST', body: form })
    } catch {
      toast.warning('Le ticket a été créé mais la pièce jointe n’a pas pu être envoyée.')
    }
  }

  const onSubmit = (values: TicketCreateInput) => {
    setFormError(null)
    createTicket.mutate(values, {
      onSuccess: async (ticket) => {
        if (imageFile) await uploadAttachment(ticket, imageFile)
        toast.success('Ticket créé.')
        navigate(`/tickets/${ticket.id}`)
      },
      onError: (err) => {
        // US04-AC3 — a direct API call with the same invalid content is rejected 400.
        if (err instanceof ApiError && err.isValidation) {
          setFormError(err.message)
        } else {
          setFormError('La création du ticket a échoué.')
        }
      },
    })
  }

  return (
    <section className="mx-auto max-w-2xl space-y-4">
      <h1 className="text-xl font-semibold">Nouveau ticket</h1>
      <Card>
        <CardHeader>
          <CardTitle className="text-base">Signaler un besoin ou un incident</CardTitle>
        </CardHeader>
        <CardContent>
          {/* noValidate: validation is driven by zod so messages are announced consistently. */}
          <form className="space-y-4" onSubmit={handleSubmit(onSubmit)} noValidate aria-label="Création d'un ticket">
            <div className="space-y-1">
              <Label htmlFor="title">Titre</Label>
              <Input
                id="title"
                aria-invalid={Boolean(errors.title)}
                aria-describedby={errors.title ? 'title-error' : undefined}
                {...register('title')}
              />
              {errors.title && (
                <p id="title-error" role="alert" className="text-sm text-destructive">
                  {errors.title.message}
                </p>
              )}
            </div>

            <div className="space-y-1">
              <Label htmlFor="category">Catégorie</Label>
              <select
                id="category"
                className="h-8 w-full rounded-md border border-input bg-background px-2 text-sm"
                {...register('category', {
                  setValueAs: (v) => (v === '' ? undefined : v),
                })}
              >
                <option value="">— Choisir —</option>
                {TICKET_CATEGORIES.map((c) => (
                  <option key={c} value={c}>
                    {c}
                  </option>
                ))}
              </select>
            </div>

            <div className="space-y-1">
              <Label htmlFor="location">Localisation</Label>
              <Input id="location" {...register('location')} placeholder="Bâtiment, salle…" />
            </div>

            <div className="space-y-1">
              <Label htmlFor="description">Description</Label>
              <Textarea
                id="description"
                rows={5}
                aria-invalid={Boolean(errors.description)}
                aria-describedby={errors.description ? 'description-error' : undefined}
                {...register('description')}
              />
              {errors.description && (
                <p id="description-error" role="alert" className="text-sm text-destructive">
                  {errors.description.message}
                </p>
              )}
            </div>

            <div className="space-y-1">
              <Label htmlFor="attachment">Pièce jointe (image JPG/PNG, 10 Mo max)</Label>
              <Input
                id="attachment"
                type="file"
                accept="image/jpeg,image/png"
                onChange={onImageChange}
                aria-describedby={imageError ? 'attachment-error' : undefined}
              />
              {imageFile && <p className="text-xs text-muted-foreground">Sélectionné : {imageFile.name}</p>}
              {imageError && (
                <p id="attachment-error" role="alert" className="text-sm text-destructive">
                  {imageError}
                </p>
              )}
            </div>

            {formError && (
              <p role="alert" className="text-sm text-destructive">
                {formError}
              </p>
            )}

            <Button type="submit" disabled={createTicket.isPending}>
              {createTicket.isPending ? 'Création…' : 'Créer le ticket'}
            </Button>
          </form>
        </CardContent>
      </Card>
    </section>
  )
}
