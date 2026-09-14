<script setup>
import ChannelIcon from 'dashboard/components-next/icon/ChannelIcon.vue';

defineProps({
  inbox: {
    type: Object,
    default: () => {},
  },
});
</script>

<template>
  <div :title="inbox.name" class="flex items-center gap-0.5 min-w-0">
    <ChannelIcon :inbox="inbox" use-brand-icon class="size-4 flex-shrink-0" />
    <span class="truncate text-label-small text-n-slate-11">
      {{ inbox.name }}
    </span>
  </div>
</template>
