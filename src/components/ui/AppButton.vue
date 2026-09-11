<script setup lang="ts">
import { computed } from "vue";
import { RouterLink, type RouteLocationRaw } from "vue-router";

const props = withDefaults(
  defineProps<{
    variant?: "primary" | "secondary" | "ghost";
    size?: "sm" | "md" | "lg";
    type?: "button" | "submit";
    disabled?: boolean;
    loading?: boolean;
    block?: boolean;
    /** Render as a RouterLink (internal nav) — anchor semantics. */
    to?: RouteLocationRaw;
    /** Render as a plain anchor (external / same-page). */
    href?: string;
  }>(),
  { variant: "primary", size: "md", type: "button", to: undefined, href: undefined },
);

const classes = computed(() => {
  const base =
    "inline-flex items-center justify-center gap-1.5 font-medium rounded-lg transition-colors focus-ring disabled:opacity-50 disabled:cursor-not-allowed";
  const size = {
    sm: "px-3 py-1.5 text-13",
    md: "px-3.5 py-2 text-13.5",
    lg: "px-5 py-2.5 text-14.5",
  }[props.size];
  const variant = {
    primary: "bg-ink text-white hover:bg-black",
    secondary: "border border-line text-ink-soft hover:bg-[#FBFBFA]",
    ghost: "text-ink-soft hover:bg-[#F3F3F0]",
  }[props.variant];
  return [base, size, variant, props.block ? "w-full" : ""];
});

const spinner = computed(() => props.loading);
</script>

<template>
  <RouterLink
    v-if="props.to"
    :to="props.to"
    :class="classes"
  >
    <slot />
  </RouterLink>
  <a
    v-else-if="props.href"
    :href="props.href"
    :class="classes"
  >
    <slot />
  </a>
  <button
    v-else
    :type="props.type"
    :disabled="props.disabled || props.loading"
    :class="classes"
  >
    <span
      v-if="spinner"
      class="inline-block w-3.5 h-3.5 rounded-full border-2 border-current border-r-transparent animate-spin"
    />
    <slot />
  </button>
</template>
