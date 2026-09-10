"use client"

import { useQuery } from "@tanstack/react-query"

import { Skeleton } from "@/components/ui/skeleton"
import { api } from "@/lib/api"

export function ItemSummary() {
  const { data, isPending, isError } = useQuery({
    queryKey: ["items"],
    queryFn: () => api.listItems({ limit: 100 }),
  })

  if (isPending) return <Skeleton className="h-8 w-40" />
  if (isError) return <p className="text-sm text-muted-foreground">Unavailable</p>

  const done = data.items.filter((item) => item.is_done).length

  return (
    <div className="flex items-baseline gap-6">
      <div>
        <p className="text-3xl font-semibold tabular-nums">{data.total}</p>
        <p className="text-sm text-muted-foreground">total</p>
      </div>
      <div>
        <p className="text-3xl font-semibold tabular-nums">{done}</p>
        <p className="text-sm text-muted-foreground">done</p>
      </div>
    </div>
  )
}
