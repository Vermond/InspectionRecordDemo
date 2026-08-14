import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { withSupabase } from "jsr:@supabase/server@^1"

interface SyncInspectionRequest {
  id: string
  targetId: string
  targetNameSnapshot: string
  equipmentNumberSnapshot: string
  status: string | null
  memo: string
  latitude: number | null
  longitude: number | null
  createdAt: string
  updatedAt: string
}

export default {
  fetch: withSupabase(
    { auth: "publishable" },
    async (req, ctx) => {
      if (req.method !== "POST") {
        return Response.json(
          { error: "Method not allowed" },
          { status: 405 }
        )
      }

      const formData = await req.formData()

      const recordValue = formData.get("record")
      const photoActionValue = formData.get("photoAction")
      const photoValue = formData.get("photo")

      if (typeof recordValue !== "string") {
        return Response.json(
          {
            success: false,
            code: "INVALID_RECORD",
          },
          { status: 400 }
        )
      }

      if (typeof photoActionValue !== "string") {
        return Response.json(
          {
            success: false,
            code: "INVALID_PHOTO_ACTION",
          },
          { status: 400 }
        )
      }

      if (!["keep", "upload", "delete"].includes(photoActionValue)) {
        return Response.json(
          {
            success: false,
            code: "INVALID_PHOTO_ACTION",
          },
          { status: 400 }
        )
      }

      let record: SyncInspectionRequest

      try {
        record = JSON.parse(recordValue)
      } catch {
        return Response.json(
          {
            success: false,
            code: "INVALID_RECORD_JSON",
          },
          { status: 400 }
        )
      }

      const photoAction = photoActionValue


      if (photoAction === "upload" && !(photoValue instanceof File)) {
        return Response.json(
          {
            success: false,
            code: "PHOTO_REQUIRED",
          },
          { status: 400 }
        )
      }

      const photo = photoValue instanceof File ? photoValue : null

      const photoPath = `inspection-records/${record.id}/photo.jpg`

      if (photoAction === "upload" && photo) {
        const { error: uploadError } = await ctx.supabase.storage
          .from("inspection-photos")
          .upload(photoPath, photo, {
            contentType: "image/jpeg",
            upsert: true,
          })

        if (uploadError) {
          console.error(uploadError)

          return Response.json(
            {
              success: false,
              code: "PHOTO_UPLOAD_FAILED",
            },
            { status: 500 }
          )
        }
      }

      const payload: Record<string, unknown> = {
        id: record.id,
        target_id: record.targetId,
        target_name_snapshot: record.targetNameSnapshot,
        equipment_number_snapshot: record.equipmentNumberSnapshot,
        status: record.status,
        memo: record.memo,
        latitude: record.latitude,
        longitude: record.longitude,
        created_at: record.createdAt,
        updated_at: record.updatedAt,
      }

      if (photoAction === "upload") {
        payload.photo_path = photoPath
      } else if (photoAction === "delete") {
        payload.photo_path = null
      }

      const { data, error } = await ctx.supabase
        .from("inspection_records")
        .upsert(payload)
        .select()
        .single()

      if (error) {
        console.error(error)

        return Response.json(
          {
            success: false,
            code: "DATABASE_ERROR",
            retryable: true,
          },
          { status: 500 }
        )
      }

      if (photoAction === "delete") {
        const { error: deleteError } = await ctx.supabase.storage
          .from("inspection-photos")
          .remove([photoPath])

        if (deleteError) {
          console.error(deleteError)

          return Response.json(
            {
              success: false,
              code: "PHOTO_DELETE_FAILED",
              retryable: true,
            },
            { status: 500 }
          )
        }
      }

      return Response.json({
        success: true,
        record: data,
      })
    }
  ),
}
