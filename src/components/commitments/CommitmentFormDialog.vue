<script setup lang="ts">
import { computed, reactive, ref, watch } from "vue";
import { DateTime } from "luxon";
import { useCreateCommitment, useUpdateCommitment } from "@/composables/useCommitments";
import { useToast } from "@/composables/useToast";
import { useMoney } from "@/composables/useMoney";
import { toAppError } from "@/lib/errors";
import type { Commitment } from "@/services/commitments";
import type { CommitmentKind } from "@/types/database";
import type { MemberDirectoryEntry } from "@/types/derived";
import AppModal from "@/components/ui/AppModal.vue";
import AppButton from "@/components/ui/AppButton.vue";

const props = defineProps<{
  open: boolean;
  projectId: string;
  currency: string;
  timezone: string;
  memberOptions: MemberDirectoryEntry[];
  /** null = create mode */
  commitment: Commitment | null;
}>();
const emit = defineEmits<{ close: [] }>();

const KINDS: { value: CommitmentKind; label: string }[] = [
  { value: "accommodation", label: "Accommodation" },
  { value: "transport", label: "Transport" },
  { value: "food", label: "Food" },
  { value: "experience", label: "Experience" },
  { value: "services", label: "Services" },
  { value: "other", label: "Other" },
];

const create = useCreateCommitment(props.projectId);
const update = useUpdateCommitment(props.projectId);
const toast = useToast();
const { toMinor, toMajor } = useMoney();

const ownerCandidates = computed(() => props.memberOptions.filter((m) => m.role !== "viewer" && m.status === "active"));

function localInput(iso: string | null, allDay: boolean): string {
  if (!iso) return "";
  const dt = DateTime.fromISO(iso, { zone: props.timezone });
  return dt.toFormat(allDay ? "yyyy-LL-dd" : "yyyy-LL-dd'T'HH:mm");
}

const form = reactive({
  title: "",
  kind: "other" as CommitmentKind,
  owner_member_id: "" as string,
  is_all_day: false,
  starts_at: "",
  ends_at: "",
  location_label: "",
  location_address: "",
  supplier_name: "",
  supplier_contact: "",
  booking_reference: "",
  booking_confirmed: false,
  estimated_cost_major: "",
  notes: "",
});
const fieldError = ref<string | null>(null);

function resetFromCommitment() {
  const c = props.commitment;
  if (!c) {
    Object.assign(form, {
      title: "",
      kind: "other",
      owner_member_id: "",
      is_all_day: false,
      starts_at: "",
      ends_at: "",
      location_label: "",
      location_address: "",
      supplier_name: "",
      supplier_contact: "",
      booking_reference: "",
      booking_confirmed: false,
      estimated_cost_major: "",
      notes: "",
    });
    return;
  }
  form.title = c.title;
  form.kind = c.kind;
  form.owner_member_id = c.owner_member_id ?? "";
  form.is_all_day = c.is_all_day;
  form.starts_at = localInput(c.starts_at, c.is_all_day);
  form.ends_at = localInput(c.ends_at, c.is_all_day);
  form.location_label = c.location_label ?? "";
  form.location_address = c.location_address ?? "";
  form.supplier_name = c.supplier_name ?? "";
  form.supplier_contact = c.supplier_contact ?? "";
  form.booking_reference = c.booking_reference ?? "";
  form.booking_confirmed = c.booking_confirmed;
  const major = toMajor(c.estimated_cost_minor, props.currency);
  form.estimated_cost_major = major != null ? String(major) : "";
  form.notes = c.notes ?? "";
}
watch(() => [props.open, props.commitment], resetFromCommitment, { immediate: true });

function toIso(local: string, allDay: boolean): string | null {
  if (!local) return null;
  const dt = allDay
    ? DateTime.fromFormat(local, "yyyy-LL-dd", { zone: props.timezone })
    : DateTime.fromFormat(local, "yyyy-LL-dd'T'HH:mm", { zone: props.timezone });
  return dt.isValid ? dt.toUTC().toISO() : null;
}

async function submit() {
  fieldError.value = null;
  if (!form.title.trim()) {
    fieldError.value = "Give the activity a title.";
    return;
  }
  const startsAt = toIso(form.starts_at, form.is_all_day);
  const endsAt = toIso(form.ends_at, form.is_all_day);
  if (startsAt && endsAt && endsAt < startsAt) {
    fieldError.value = "The end must be on or after the start.";
    return;
  }
  const estimatedCost = form.estimated_cost_major.trim() ? toMinor(form.estimated_cost_major, props.currency) : null;
  if (form.estimated_cost_major.trim() && (estimatedCost == null || estimatedCost < 0)) {
    fieldError.value = "Estimated cost must be a valid, non-negative amount.";
    return;
  }

  const payload = {
    title: form.title.trim(),
    kind: form.kind,
    owner_member_id: form.owner_member_id || null,
    is_all_day: form.is_all_day,
    starts_at: startsAt,
    ends_at: endsAt,
    location_label: form.location_label.trim() || null,
    location_address: form.location_address.trim() || null,
    supplier_name: form.supplier_name.trim() || null,
    supplier_contact: form.supplier_contact.trim() || null,
    booking_reference: form.booking_reference.trim() || null,
    booking_confirmed: form.booking_confirmed,
    estimated_cost_minor: estimatedCost,
    notes: form.notes.trim() || null,
  };

  try {
    if (props.commitment) {
      await update.mutateAsync({ id: props.commitment.id, patch: payload });
      toast.success("Activity updated.");
    } else {
      await create.mutateAsync({ ...payload, project_id: props.projectId });
      toast.success("Activity created.");
    }
    emit("close");
  } catch (e) {
    fieldError.value = toAppError(e).message;
  }
}

const isPending = computed(() => create.isPending.value || update.isPending.value);
</script>

<template>
  <AppModal :open="props.open" :title="props.commitment ? 'Edit activity' : 'New activity'" size="lg" @close="emit('close')">
    <form class="space-y-4" @submit.prevent="submit">
      <label class="block">
        <span class="text-13 font-medium block mb-1.5 text-ink-soft">Title</span>
        <input v-model="form.title" required class="w-full border rounded-lg px-3.5 py-2.5 text-14 focus-ring border-line" />
      </label>

      <div class="grid grid-cols-2 gap-3">
        <label class="block">
          <span class="text-13 font-medium block mb-1.5 text-ink-soft">Kind</span>
          <select v-model="form.kind" class="w-full border rounded-lg px-3 py-2.5 text-14 focus-ring border-line bg-surface">
            <option v-for="k in KINDS" :key="k.value" :value="k.value">{{ k.label }}</option>
          </select>
        </label>
        <label class="block">
          <span class="text-13 font-medium block mb-1.5 text-ink-soft">Owner</span>
          <select
            v-model="form.owner_member_id"
            class="w-full border rounded-lg px-3 py-2.5 text-14 focus-ring border-line bg-surface"
          >
            <option value="">Unassigned</option>
            <option v-for="m in ownerCandidates" :key="m.member_id" :value="m.member_id">{{ m.display_name }}</option>
          </select>
        </label>
      </div>

      <label class="flex items-center gap-2 text-13.5 text-ink-soft">
        <input v-model="form.is_all_day" type="checkbox" class="rounded border-line" />
        All day
      </label>
      <div class="grid grid-cols-2 gap-3">
        <label class="block">
          <span class="text-13 font-medium block mb-1.5 text-ink-soft">Starts</span>
          <input
            v-model="form.starts_at"
            :type="form.is_all_day ? 'date' : 'datetime-local'"
            class="w-full border rounded-lg px-3 py-2.5 text-14 focus-ring border-line"
          />
        </label>
        <label class="block">
          <span class="text-13 font-medium block mb-1.5 text-ink-soft">Ends</span>
          <input
            v-model="form.ends_at"
            :type="form.is_all_day ? 'date' : 'datetime-local'"
            class="w-full border rounded-lg px-3 py-2.5 text-14 focus-ring border-line"
          />
        </label>
      </div>

      <div class="grid grid-cols-2 gap-3">
        <label class="block">
          <span class="text-13 font-medium block mb-1.5 text-ink-soft">Location name</span>
          <input v-model="form.location_label" class="w-full border rounded-lg px-3.5 py-2.5 text-14 focus-ring border-line" />
        </label>
        <label class="block">
          <span class="text-13 font-medium block mb-1.5 text-ink-soft">Address</span>
          <input v-model="form.location_address" class="w-full border rounded-lg px-3.5 py-2.5 text-14 focus-ring border-line" />
        </label>
      </div>

      <div class="grid grid-cols-2 gap-3">
        <label class="block">
          <span class="text-13 font-medium block mb-1.5 text-ink-soft">Supplier</span>
          <input v-model="form.supplier_name" class="w-full border rounded-lg px-3.5 py-2.5 text-14 focus-ring border-line" />
        </label>
        <label class="block">
          <span class="text-13 font-medium block mb-1.5 text-ink-soft">Supplier contact</span>
          <input v-model="form.supplier_contact" class="w-full border rounded-lg px-3.5 py-2.5 text-14 focus-ring border-line" />
        </label>
      </div>

      <div class="grid grid-cols-2 gap-3">
        <label class="block">
          <span class="text-13 font-medium block mb-1.5 text-ink-soft">Booking reference</span>
          <input v-model="form.booking_reference" class="w-full border rounded-lg px-3.5 py-2.5 text-14 focus-ring border-line" />
        </label>
        <label class="block">
          <span class="text-13 font-medium block mb-1.5 text-ink-soft">Estimated cost ({{ props.currency }})</span>
          <input
            v-model="form.estimated_cost_major"
            type="number"
            step="0.01"
            min="0"
            class="w-full border rounded-lg px-3.5 py-2.5 text-14 focus-ring border-line"
          />
        </label>
      </div>

      <label class="flex items-center gap-2 text-13.5 text-ink-soft">
        <input v-model="form.booking_confirmed" type="checkbox" class="rounded border-line" />
        Booking confirmed
      </label>

      <label class="block">
        <span class="text-13 font-medium block mb-1.5 text-ink-soft">Notes</span>
        <textarea v-model="form.notes" rows="2" class="w-full border rounded-lg px-3.5 py-2.5 text-14 focus-ring border-line" />
      </label>

      <p v-if="fieldError" class="text-13 text-danger">{{ fieldError }}</p>
    </form>

    <template #footer>
      <AppButton variant="secondary" size="sm" @click="emit('close')">Cancel</AppButton>
      <AppButton size="sm" :loading="isPending" @click="submit">{{ props.commitment ? "Save" : "Create activity" }}</AppButton>
    </template>
  </AppModal>
</template>
