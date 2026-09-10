<script setup lang="ts">
import { computed, reactive, ref, watch } from "vue";
import { DateTime } from "luxon";
import { useCreateCommitment, useUpdateCommitment } from "@/composables/useCommitments";
import { useToast } from "@/composables/useToast";
import { useMoney } from "@/composables/useMoney";
import { toAppError } from "@/lib/errors";
import { ACTIVITY_WORKFLOWS, activityWorkflow, defaultActivityTypeForProjectProfile } from "@/lib/activityWorkflows";
import { COMMITMENT_CATEGORY_OPTIONS, DEFAULT_COMMITMENT_KIND } from "@/lib/commitmentCategories";
import { REPEAT_OPTIONS, repeatOption, repeatOptionFromParts, type RepeatOptionValue } from "@/lib/recurrence";
import type { Commitment } from "@/services/commitments";
import type { ActivityType, CommitmentKind, ProjectProfile } from "@/types/database";
import type { MemberDirectoryEntry } from "@/types/derived";
import AppModal from "@/components/ui/AppModal.vue";
import AppButton from "@/components/ui/AppButton.vue";

const props = defineProps<{
  open: boolean;
  projectId: string;
  currency: string;
  timezone: string;
  projectProfile: ProjectProfile;
  memberOptions: MemberDirectoryEntry[];
  /** null = create mode */
  commitment: Commitment | null;
}>();
const emit = defineEmits<{ close: [] }>();

const create = useCreateCommitment(props.projectId);
const update = useUpdateCommitment(props.projectId);
const toast = useToast();
const { toMinor, toMajor } = useMoney();

const ownerCandidates = computed(() => props.memberOptions.filter((m) => m.role !== "viewer" && m.status === "active"));
const defaultActivityType = computed(() => defaultActivityTypeForProjectProfile(props.projectProfile));

function localDateInput(iso: string | null): string {
  if (!iso) return "";
  const dt = DateTime.fromISO(iso, { zone: props.timezone });
  return dt.toFormat("yyyy-LL-dd");
}

const form = reactive({
  title: "",
  activity_type: defaultActivityType.value as ActivityType,
  kind: DEFAULT_COMMITMENT_KIND as CommitmentKind,
  owner_member_id: "" as string,
  starts_at: "",
  ends_at: "",
  location_label: "",
  location_address: "",
  supplier_name: "",
  supplier_contact: "",
  booking_reference: "",
  booking_confirmed: false,
  estimated_cost_major: "",
  repeat: "none" as RepeatOptionValue,
  notes: "",
});
const fieldError = ref<string | null>(null);
const showEndDate = ref(false);
const showLocation = ref(false);
const showSupplier = ref(false);
const showCost = ref(false);
const selectedWorkflow = computed(() => activityWorkflow(form.activity_type));
const dateLabel = computed(() => (form.activity_type === "task" || form.activity_type === "purchase" ? "Due date" : "Date"));

function syncDisclosureFromWorkflow() {
  const fields = selectedWorkflow.value.preferredFields;
  showEndDate.value = fields.endDate || !!form.ends_at;
  showLocation.value = fields.location || !!(form.location_label || form.location_address);
  showSupplier.value = fields.supplier || fields.booking || !!(form.supplier_name || form.supplier_contact || form.booking_reference || form.booking_confirmed);
  showCost.value = fields.cost || !!form.estimated_cost_major;
}

function hasLocation(c: Commitment): boolean {
  return !!(c.location_label || c.location_address);
}

function hasSupplierBooking(c: Commitment): boolean {
  return !!(c.supplier_name || c.supplier_contact || c.booking_reference || c.booking_confirmed);
}

function hasCost(c: Commitment): boolean {
  return c.estimated_cost_minor != null;
}

function resetFromCommitment() {
  const c = props.commitment;
  if (!c) {
    Object.assign(form, {
      title: "",
      activity_type: defaultActivityType.value,
      kind: DEFAULT_COMMITMENT_KIND,
      owner_member_id: "",
      starts_at: "",
      ends_at: "",
      location_label: "",
      location_address: "",
      supplier_name: "",
      supplier_contact: "",
      booking_reference: "",
      booking_confirmed: false,
      estimated_cost_major: "",
      repeat: "none",
      notes: "",
    });
    syncDisclosureFromWorkflow();
    return;
  }
  form.title = c.title;
  form.activity_type = c.activity_type;
  form.kind = c.kind;
  form.owner_member_id = c.owner_member_id ?? "";
  form.starts_at = localDateInput(c.starts_at);
  form.ends_at = localDateInput(c.ends_at);
  form.location_label = c.location_label ?? "";
  form.location_address = c.location_address ?? "";
  form.supplier_name = c.supplier_name ?? "";
  form.supplier_contact = c.supplier_contact ?? "";
  form.booking_reference = c.booking_reference ?? "";
  form.booking_confirmed = c.booking_confirmed;
  const major = toMajor(c.estimated_cost_minor, props.currency);
  form.estimated_cost_major = major != null ? String(major) : "";
  form.repeat = repeatOptionFromParts(c.recurrence_frequency, c.recurrence_interval);
  form.notes = c.notes ?? "";
  showEndDate.value = !!c.ends_at;
  showLocation.value = hasLocation(c);
  showSupplier.value = hasSupplierBooking(c);
  showCost.value = hasCost(c);
}
watch(() => [props.open, props.commitment], resetFromCommitment, { immediate: true });

function toIsoDate(local: string): string | null {
  if (!local) return null;
  const dt = DateTime.fromFormat(local, "yyyy-LL-dd", { zone: props.timezone }).startOf("day");
  return dt.isValid ? dt.toUTC().toISO() : null;
}

function onActivityTypeChange() {
  syncDisclosureFromWorkflow();
}

async function submit() {
  if (isPending.value) return;
  fieldError.value = null;
  if (!form.title.trim()) {
    fieldError.value = "Give the activity a title.";
    return;
  }
  const startsAt = toIsoDate(form.starts_at);
  const endsAt = toIsoDate(form.ends_at);
  if (startsAt && endsAt && endsAt < startsAt) {
    fieldError.value = "The end must be on or after the start.";
    return;
  }
  const repeat = repeatOption(form.repeat);
  if (repeat.value !== "none" && !form.starts_at) {
    fieldError.value = "Choose a date before making this activity repeat.";
    return;
  }
  const estimatedCost = form.estimated_cost_major.trim() ? toMinor(form.estimated_cost_major, props.currency) : null;
  if (form.estimated_cost_major.trim() && (estimatedCost == null || estimatedCost < 0)) {
    fieldError.value = "Estimated cost must be a valid, non-negative amount.";
    return;
  }

  const payload = {
    title: form.title.trim(),
    activity_type: form.activity_type,
    kind: form.kind,
    owner_member_id: form.owner_member_id || null,
    is_all_day: true,
    starts_at: startsAt,
    ends_at: endsAt,
    location_label: form.location_label.trim() || null,
    location_address: form.location_address.trim() || null,
    supplier_name: form.supplier_name.trim() || null,
    supplier_contact: form.supplier_contact.trim() || null,
    booking_reference: form.booking_reference.trim() || null,
    booking_confirmed: form.booking_confirmed,
    estimated_cost_minor: estimatedCost,
    recurrence_frequency: repeat.frequency,
    recurrence_interval: repeat.interval,
    recurrence_start_date: repeat.value === "none" ? null : form.starts_at,
    recurrence_end_date: repeat.value === "none" ? null : props.commitment?.recurrence_end_date ?? null,
    recurrence_active: repeat.value === "none" ? true : props.commitment?.recurrence_active ?? true,
    notes: form.notes.trim() || null,
  };

  try {
    if (props.commitment) {
      await update.mutateAsync({ id: props.commitment.id, patch: payload });
      toast.success("Activity updated.");
    } else {
      await create.mutateAsync({ ...payload, project_id: props.projectId, status: selectedWorkflow.value.defaultStatus });
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
  <AppModal :busy="isPending" :open="props.open" :title="props.commitment ? 'Edit activity' : 'New activity'" size="lg" @close="emit('close')">
    <form class="space-y-4" @submit.prevent="submit">
      <label class="block">
        <span class="text-13 font-medium block mb-1.5 text-ink-soft">Title *</span>
        <input
          v-model="form.title"
          required
          maxlength="120"
          class="w-full border rounded-lg px-3.5 py-2.5 text-14 focus-ring border-line"
        />
      </label>

      <div class="grid gap-3 sm:grid-cols-2">
        <label class="block">
          <span class="text-13 font-medium block mb-1.5 text-ink-soft">Activity Type</span>
          <select
            v-model="form.activity_type"
            class="w-full border rounded-lg px-3 py-2.5 text-14 focus-ring border-line bg-surface"
            @change="onActivityTypeChange"
          >
            <option v-for="type in ACTIVITY_WORKFLOWS" :key="type.value" :value="type.value">{{ type.label }}</option>
          </select>
          <span class="text-12 text-muted mt-1 block">Controls how this activity behaves.</span>
        </label>
        <label class="block">
          <span class="text-13 font-medium block mb-1.5 text-ink-soft">Category</span>
          <select v-model="form.kind" class="w-full border rounded-lg px-3 py-2.5 text-14 focus-ring border-line bg-surface">
            <option v-for="k in COMMITMENT_CATEGORY_OPTIONS" :key="k.value" :value="k.value">{{ k.label }}</option>
          </select>
          <span class="text-12 text-muted mt-1 block">Groups this activity within the project.</span>
        </label>
      </div>

      <div class="grid gap-3 sm:grid-cols-2">
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

      <div class="grid gap-3 sm:grid-cols-2">
        <label class="block">
          <span class="text-13 font-medium block mb-1.5 text-ink-soft">{{ dateLabel }}</span>
          <input
            v-model="form.starts_at"
            type="date"
            class="w-full border rounded-lg px-3 py-2.5 text-14 focus-ring border-line"
          />
        </label>
        <label class="block">
          <span class="text-13 font-medium block mb-1.5 text-ink-soft">Repeat</span>
          <select
            v-model="form.repeat"
            class="w-full border rounded-lg px-3 py-2.5 text-14 focus-ring border-line bg-surface"
          >
            <option v-for="option in REPEAT_OPTIONS" :key="option.value" :value="option.value">
              {{ option.label }}
            </option>
          </select>
        </label>
      </div>

      <label class="block">
        <span class="text-13 font-medium block mb-1.5 text-ink-soft">Notes</span>
        <textarea v-model="form.notes" rows="2" class="w-full border rounded-lg px-3.5 py-2.5 text-14 focus-ring border-line" />
      </label>

      <div class="border-t border-line pt-4">
        <h3 class="text-13 font-semibold text-ink-soft uppercase tracking-wide">Additional details</h3>
        <div class="mt-3 space-y-3">
          <section>
            <button
              type="button"
              class="text-14 font-medium text-accent focus-ring"
              :aria-expanded="showEndDate"
              @click="showEndDate = !showEndDate"
            >
              {{ showEndDate ? "− Hide end date" : "+ Add end date" }}
            </button>
            <label v-if="showEndDate" class="block mt-2">
              <span class="text-13 font-medium block mb-1.5 text-ink-soft">End date</span>
              <input
                v-model="form.ends_at"
                type="date"
                class="w-full border rounded-lg px-3 py-2.5 text-14 focus-ring border-line"
              />
            </label>
          </section>

          <section>
            <button
              type="button"
              class="text-14 font-medium text-accent focus-ring"
              :aria-expanded="showLocation"
              @click="showLocation = !showLocation"
            >
              {{ showLocation ? "− Hide location" : "+ Add location" }}
            </button>
            <div v-if="showLocation" class="mt-2 grid gap-3 sm:grid-cols-2">
              <label class="block">
                <span class="text-13 font-medium block mb-1.5 text-ink-soft">Location name</span>
                <input v-model="form.location_label" class="w-full border rounded-lg px-3.5 py-2.5 text-14 focus-ring border-line" />
              </label>
              <label class="block">
                <span class="text-13 font-medium block mb-1.5 text-ink-soft">Address</span>
                <input v-model="form.location_address" class="w-full border rounded-lg px-3.5 py-2.5 text-14 focus-ring border-line" />
              </label>
            </div>
          </section>

          <section>
            <button
              type="button"
              class="text-14 font-medium text-accent focus-ring"
              :aria-expanded="showSupplier"
              @click="showSupplier = !showSupplier"
            >
              {{ showSupplier ? "− Hide supplier / booking" : "+ Add supplier / booking" }}
            </button>
            <div v-if="showSupplier" class="mt-2 space-y-3">
              <div class="grid gap-3 sm:grid-cols-2">
                <label class="block">
                  <span class="text-13 font-medium block mb-1.5 text-ink-soft">Supplier</span>
                  <input v-model="form.supplier_name" class="w-full border rounded-lg px-3.5 py-2.5 text-14 focus-ring border-line" />
                </label>
                <label class="block">
                  <span class="text-13 font-medium block mb-1.5 text-ink-soft">Supplier contact</span>
                  <input v-model="form.supplier_contact" class="w-full border rounded-lg px-3.5 py-2.5 text-14 focus-ring border-line" />
                </label>
              </div>
              <label class="block">
                <span class="text-13 font-medium block mb-1.5 text-ink-soft">
                  {{ selectedWorkflow.preferredFields.booking ? "Booking reference" : "Reference" }}
                </span>
                <input v-model="form.booking_reference" class="w-full border rounded-lg px-3.5 py-2.5 text-14 focus-ring border-line" />
              </label>
              <label v-if="selectedWorkflow.preferredFields.booking || form.booking_confirmed" class="flex items-center gap-2 text-13.5 text-ink-soft">
                <input v-model="form.booking_confirmed" type="checkbox" class="rounded border-line" />
                Booking confirmed
              </label>
            </div>
          </section>

          <section>
            <button
              type="button"
              class="text-14 font-medium text-accent focus-ring"
              :aria-expanded="showCost"
              @click="showCost = !showCost"
            >
              {{ showCost ? "− Hide estimated cost" : "+ Add estimated cost" }}
            </button>
            <label v-if="showCost" class="block mt-2">
              <span class="text-13 font-medium block mb-1.5 text-ink-soft">Estimated cost ({{ props.currency }})</span>
              <input
                v-model="form.estimated_cost_major"
                type="number"
                step="0.01"
                min="0"
                class="w-full border rounded-lg px-3.5 py-2.5 text-14 focus-ring border-line"
              />
            </label>
          </section>
        </div>
      </div>

      <p v-if="fieldError" class="text-13 text-danger">{{ fieldError }}</p>
    </form>

    <template #footer>
      <AppButton variant="secondary" size="sm" :disabled="isPending" @click="emit('close')">Cancel</AppButton>
      <AppButton size="sm" :loading="isPending" @click="submit">{{ props.commitment ? "Save" : "Create activity" }}</AppButton>
    </template>
  </AppModal>
</template>
