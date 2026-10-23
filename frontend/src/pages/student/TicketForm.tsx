import { useState } from 'react'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { toast } from 'sonner'
import { ApiError } from '@/domain/api'
import { useApi } from '@/api/context'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'
import { TICKET_CATEGORIES, ticketCreateSchema } from '@/domain/models'
import type { Ticket, TicketCreateInput } from '@/domain/models'
import { useCreateTicket } from '@/hooks/queries'

const MAX_IMAGE_BYTES = 10 * 1024 * 1024
const ALLOWED_IMAGE_TYPES = ['image/jpeg', 'image/png']

export interface TicketFormProps {
  /** US10-AC2 — initial values coming from the chat escalation. */
  prefill?: { title?: string; description?: string }
  /** Called once the ticket (and optional attachment) is created. */
  onCreated: (ticket: Ticket) => void
  /** Id of the submit button so a dialog footer can trigger it. */
  formId?: string
  /** Hide the inline submit button when the dialog owns the action. */
  hideSubmit?: boolean
  onPendingChange?: (pending: boolean) => void
}

export function TicketForm({
  prefill,
  onCreated,
  formId = 'ticket-form',
  hideSubmit = false,
  onPendingChange,
}: TicketFormProps) {
  const api = useApi()
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
      toast.warning("Le ticket a été créé mais la pièce jointe n'a pas pu être envoyée.")
    }
  }

  const onSubmit = (values: TicketCreateInput) => {
    setFormError(null)
    onPendingChange?.(true)
    createTicket.mutate(values, {
      onSuccess: async (ticket) => {
        if (imageFile) await uploadAttachment(ticket, imageFile)
        onPendingChange?.(false)
        toast.success('Ticket créé.')
        onCreated(ticket)
      },
      onError: (err) => {
        onPendingChange?.(false)
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
    <form
      id={formId}
      className="space-y-4"
      onSubmit={handleSubmit(onSubmit)}
      noValidate
      aria-label="Création d'un ticket"
    >
      <div className="space-y-1.5">
        <Label htmlFor="title">Titre</Label>
        <Input
          id="title"
          placeholder="Résumé en quelques mots"
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

      <div className="grid gap-4 sm:grid-cols-2">
        <div className="space-y-1.5">
          <Label htmlFor="category">Catégorie</Label>
          <select
            id="category"
            className="h-9 w-full rounded-md border border-input bg-background px-2.5 text-sm"
            aria-invalid={Boolean(errors.category)}
            {...register('category', { setValueAs: (v) => (v === '' ? undefined : v) })}
          >
            <option value="">— Choisir —</option>
            {TICKET_CATEGORIES.map((c) => (
              <option key={c} value={c}>
                {c}
              </option>
            ))}
          </select>
          {errors.category && (
            <p role="alert" className="text-sm text-destructive">
              {errors.category.message}
            </p>
          )}
        </div>

        <div className="space-y-1.5">
          <Label htmlFor="location">Localisation</Label>
          <Input id="location" {...register('location')} placeholder="Bâtiment, salle…" />
        </div>
      </div>

      <div className="space-y-1.5">
        <Label htmlFor="description">Description</Label>
        <Textarea
          id="description"
          rows={5}
          placeholder="Décrivez votre besoin ou l'incident rencontré"
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

      <div className="space-y-1.5">
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

      {!hideSubmit && (
        <Button type="submit" disabled={createTicket.isPending}>
          {createTicket.isPending ? 'Création…' : 'Créer le ticket'}
        </Button>
      )}
    </form>
  )
}
