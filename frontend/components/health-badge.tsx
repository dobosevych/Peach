"use client"

import { useQuery } from "@tanstack/react-query"

import { Badge } from "@/components/ui/badge"
import { Skeleton } from "@/components/ui/skeleton"
import { api } from "@/lib/api"

export function HealthBadge() {
  const { data, isPending, isError } = useQuery({
    queryKey: ["readiness"],
    queryFn: () => api.readiness(),
    refetchInterval: 15_000,
  })

  if (isPending) return <Skeleton className="h-6 w-24" />

  if (isError || data?.database !== "ok") {
    return <Badge variant="destructive">Unavailable</Badge>
  }
  return (
    <Badge className="bg-emerald-600 text-white hover:bg-emerald-600">Connected</Badge>
  )
}
