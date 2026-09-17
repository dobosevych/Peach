"use client";

import { zodResolver } from "@hookform/resolvers/zod";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useEffect } from "react";
import { Controller, useForm } from "react-hook-form";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Field, FieldError, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { api, itemInputSchema, type Item, type ItemInput } from "@/lib/api";

type Props = {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  /** Present when editing, absent when creating. */
  item?: Item | null;
};

export function ItemFormDialog({ open, onOpenChange, item }: Props) {
  const queryClient = useQueryClient();
  const isEditing = Boolean(item);

  const form = useForm<ItemInput>({
    resolver: zodResolver(itemInputSchema),
    defaultValues: { name: "", description: "", is_done: false },
  });

  useEffect(() => {
    if (!open) return;
    form.reset({
      name: item?.name ?? "",
      description: item?.description ?? "",
      is_done: item?.is_done ?? false,
    });
  }, [open, item, form]);

  const mutation = useMutation({
    mutationFn: (values: ItemInput) =>
      item ? api.updateItem(item.id, values) : api.createItem(values),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ["items"] });
      toast.success(isEditing ? "Item updated" : "Item created");
      onOpenChange(false);
    },
    onError: (error: Error) => toast.error(error.message),
  });

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>{isEditing ? "Edit item" : "New item"}</DialogTitle>
          <DialogDescription>
            {isEditing
              ? "Update this placeholder record."
              : "Placeholder record - the real domain model replaces this later."}
          </DialogDescription>
        </DialogHeader>

        <form
          className="grid gap-4"
          onSubmit={form.handleSubmit((values) => mutation.mutate(values))}
        >
          <Field data-invalid={Boolean(form.formState.errors.name)}>
            <FieldLabel htmlFor="name">Name</FieldLabel>
            <Input id="name" autoComplete="off" {...form.register("name")} />
            {form.formState.errors.name && (
              <FieldError errors={[form.formState.errors.name]} />
            )}
          </Field>

          <Field data-invalid={Boolean(form.formState.errors.description)}>
            <FieldLabel htmlFor="description">Description</FieldLabel>
            <Textarea
              id="description"
              rows={3}
              {...form.register("description")}
            />
            {form.formState.errors.description && (
              <FieldError errors={[form.formState.errors.description]} />
            )}
          </Field>

          <Field orientation="horizontal">
            <Controller
              control={form.control}
              name="is_done"
              render={({ field }) => (
                <Checkbox
                  id="is_done"
                  checked={field.value}
                  onCheckedChange={(checked) =>
                    field.onChange(checked === true)
                  }
                />
              )}
            />
            <FieldLabel htmlFor="is_done">Done</FieldLabel>
          </Field>

          <DialogFooter>
            <Button
              type="button"
              size="lg"
              variant="outline"
              onClick={() => onOpenChange(false)}
              disabled={mutation.isPending}
            >
              Cancel
            </Button>
            <Button type="submit" size="lg" disabled={mutation.isPending}>
              {mutation.isPending
                ? "Saving..."
                : isEditing
                  ? "Save changes"
                  : "Create"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
