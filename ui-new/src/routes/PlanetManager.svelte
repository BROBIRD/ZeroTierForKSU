<script lang="ts">
  import { onMount } from "svelte";
  import { pop } from "@/lib/router";
  import { t } from "svelte-i18n";
  import {
    ArrowLeft,
    Globe,
    Plus,
    Copy,
    Pencil,
    Trash2,
    Play,
    Undo2,
    Eye,
    FileText,
    Loader2,
  } from "lucide-svelte";
  import Button from "@/lib/components/ui/button/Button.svelte";
  import Input from "@/lib/components/ui/input/Input.svelte";
  import Label from "@/lib/components/ui/label/Label.svelte";
  import { KsuApi } from "@/api/ksu";
  import type { PlanetFile, PlanetListInfo } from "@/types/zerotier";
  import { toast } from "@/stores/toast";
  import { confirm as confirmStore } from "@/stores/confirm";
  import { cn } from "@/lib/utils";

  let loading = true;
  let info: PlanetListInfo = {
    planets: [],
    usingCustom: false,
    backup: false,
    worldId: "",
    worldTimestamp: "",
  };
  let applyingName = "";

  // editor dialog state
  let editorOpen = false;
  let editorMode: "add" | "edit" | "view" = "add";
  let editorName = "";
  let editorNameOriginal = "";
  let editorContent = "";
  let editorSaving = false;

  // copy dialog state
  let copyOpen = false;
  let copySrc = "";
  let copyDst = "";
  let copySaving = false;

  function formatSize(bytes: number): string {
    if (!bytes && bytes !== 0) return "-";
    if (bytes < 1024) return `${bytes} B`;
    return `${(bytes / 1024).toFixed(1)} KB`;
  }

  function formatTime(unixSeconds: number): string {
    if (!unixSeconds) return "-";
    const diff = Date.now() - unixSeconds * 1000;
    if (diff < 60000) return $t("common.time.justNow");
    if (diff < 3600000)
      return `${Math.floor(diff / 60000)}${$t("common.time.minutes")} ${$t("common.time.ago")}`;
    if (diff < 86400000)
      return `${Math.floor(diff / 3600000)}${$t("common.time.hours")} ${$t("common.time.ago")}`;
    return `${Math.floor(diff / 86400000)}${$t("common.time.days")} ${$t("common.time.ago")}`;
  }

  async function loadPlanets() {
    loading = true;
    try {
      info = await KsuApi.planetList();
      if (KsuApi.getDebug()) console.log("[Planet] Loaded:", info);
    } catch (e: any) {
      toast.error($t("planets.toasts.loadFailed", { values: { error: e.message || e } }));
    } finally {
      loading = false;
    }
  }

  function openAdd() {
    editorMode = "add";
    editorName = "";
    editorNameOriginal = "";
    editorContent = "";
    editorOpen = true;
  }

  async function openEdit(name: string, viewOnly: boolean) {
    try {
      const content = await KsuApi.planetShow(name);
      editorMode = viewOnly ? "view" : "edit";
      editorName = name;
      editorNameOriginal = name;
      editorContent = content;
      editorOpen = true;
    } catch (e: any) {
      toast.error($t("planets.toasts.showFailed", { values: { error: e.message || e } }));
    }
  }

  function closeEditor() {
    editorOpen = false;
  }

  async function saveEditor() {
    const name = editorName.trim();
    if (!name) {
      toast.error($t("planets.toasts.nameRequired"));
      return;
    }
    if (editorMode === "add" && info.planets.some((p) => p.name === name)) {
      toast.error($t("planets.toasts.nameExists", { values: { name } }));
      return;
    }
    editorSaving = true;
    try {
      if (editorMode === "add") {
        await KsuApi.planetAdd(name, editorContent);
        toast.success($t("planets.toasts.added", { values: { name } }));
      } else if (editorMode === "edit") {
        if (name !== editorNameOriginal) {
          // rename = copy content to a new entry then drop the old one
          await KsuApi.planetCopy(editorNameOriginal, name);
          await KsuApi.planetDelete(editorNameOriginal);
        }
        await KsuApi.planetEdit(name, editorContent);
        toast.success($t("planets.toasts.updated", { values: { name } }));
      }
      editorOpen = false;
      await loadPlanets();
    } catch (e: any) {
      toast.error($t("planets.toasts.saveFailed", { values: { error: e.message || e } }));
    } finally {
      editorSaving = false;
    }
  }

  function openCopy(p: PlanetFile) {
    copySrc = p.name;
    copyDst = `${p.name}-copy`;
    copyOpen = true;
  }

  function closeCopy() {
    copyOpen = false;
  }

  async function saveCopy() {
    const dst = copyDst.trim();
    if (!dst) {
      toast.error($t("planets.toasts.nameRequired"));
      return;
    }
    if (info.planets.some((p) => p.name === dst)) {
      toast.error($t("planets.toasts.nameExists", { values: { name: dst } }));
      return;
    }
    copySaving = true;
    try {
      await KsuApi.planetCopy(copySrc, dst);
      toast.success($t("planets.toasts.copied", { values: { src: copySrc, dst } }));
      copyOpen = false;
      await loadPlanets();
    } catch (e: any) {
      toast.error($t("planets.toasts.saveFailed", { values: { error: e.message || e } }));
    } finally {
      copySaving = false;
    }
  }

  function handleApply(p: PlanetFile) {
    if (p.active) return;
    confirmStore.open({
      title: $t("planets.apply.title"),
      message: $t("planets.apply.message", { values: { name: p.name } }),
      confirmText: $t("planets.apply.confirm"),
      onConfirm: async () => {
        applyingName = p.name;
        try {
          await KsuApi.planetApply(p.name);
          toast.success($t("planets.toasts.applied", { values: { name: p.name } }));
          await loadPlanets();
        } catch (e: any) {
          toast.error($t("planets.toasts.applyFailed", { values: { error: e.message || e } }));
        } finally {
          applyingName = "";
        }
      },
    });
  }

  function handleRestore() {
    confirmStore.open({
      title: $t("planets.restore.title"),
      message: $t("planets.restore.message"),
      confirmText: $t("planets.restore.confirm"),
      onConfirm: async () => {
        try {
          await KsuApi.planetRestore();
          toast.success($t("planets.toasts.restored"));
          await loadPlanets();
        } catch (e: any) {
          toast.error($t("planets.toasts.restoreFailed", { values: { error: e.message || e } }));
        }
      },
    });
  }

  function handleDelete(p: PlanetFile) {
    confirmStore.open({
      title: $t("planets.delete.title"),
      message: $t("planets.delete.message", { values: { name: p.name } }),
      confirmText: $t("planets.delete.confirm"),
      variant: "destructive",
      onConfirm: async () => {
        try {
          await KsuApi.planetDelete(p.name);
          toast.success($t("planets.toasts.deleted", { values: { name: p.name } }));
          await loadPlanets();
        } catch (e: any) {
          toast.error($t("planets.toasts.deleteFailed", { values: { error: e.message || e } }));
        }
      },
    });
  }

  onMount(() => {
    loadPlanets();
  });
</script>

<div class="p-4 space-y-4 pb-24">
  <div
    class="sticky top-0 z-50 bg-background/95 backdrop-blur supports-[backdrop-filter]:bg-background/60 py-4 -mt-4 -mx-4 px-4 border-b mb-6 flex items-center justify-between"
  >
    <div class="flex items-center gap-2">
      <Button variant="ghost" size="icon" on:click={() => pop()}>
        <ArrowLeft class="h-6 w-6" />
      </Button>
      <h1 class="text-2xl font-bold tracking-tight">{$t("planets.title")}</h1>
    </div>
    <Button size="sm" on:click={openAdd}>
      <Plus class="h-4 w-4 mr-1" />
      {$t("planets.add")}
    </Button>
  </div>

  <!-- Current planet status -->
  <div class="rounded-xl border bg-card text-card-foreground shadow-sm p-4">
    <div class="flex items-start justify-between gap-3">
      <div class="flex items-center gap-3">
        <div
          class={cn(
            "p-2 rounded-full",
            info.usingCustom
              ? "bg-amber-500/10 text-amber-600"
              : "bg-primary/10 text-primary",
          )}
        >
          <Globe class="h-5 w-5" />
        </div>
        <div>
          <div class="font-medium">
            {info.usingCustom
              ? $t("planets.status.customActive")
              : $t("planets.status.defaultActive")}
          </div>
          <div class="text-xs text-muted-foreground">
            {$t("planets.status.desc")}
          </div>
        </div>
      </div>
      {#if info.usingCustom && info.backup}
        <Button
          variant="outline"
          size="sm"
          class="h-8"
          on:click={handleRestore}
        >
          <Undo2 class="h-4 w-4 mr-1" />
          {$t("planets.restore.button")}
        </Button>
      {/if}
    </div>
    {#if info.worldId}
      <div
        class="mt-3 flex flex-wrap gap-x-6 gap-y-1 text-xs text-muted-foreground border-t pt-3"
      >
        <span>
          {$t("planets.status.worldId")}:
          <span class="font-mono text-foreground">{info.worldId}</span>
        </span>
        {#if info.worldTimestamp}
          <span>
            {$t("planets.status.worldTime")}:
            <span class="font-mono text-foreground">{formatTime(Number(info.worldTimestamp))}</span>
          </span>
        {/if}
      </div>
    {/if}
  </div>

  {#if loading}
    <div class="text-center py-12 text-muted-foreground flex flex-col items-center gap-2">
      <Loader2 class="h-8 w-8 animate-spin opacity-50" />
      <span>{$t("common.loading")}</span>
    </div>
  {:else if info.planets.length === 0}
    <div
      class="text-center py-12 text-muted-foreground border-2 border-dashed rounded-xl flex flex-col items-center gap-2"
    >
      <FileText class="h-10 w-10 opacity-20" />
      <span>{$t("planets.noPlanets")}</span>
      <Button variant="outline" size="sm" on:click={openAdd}>
        <Plus class="h-4 w-4 mr-1" />
        {$t("planets.add")}
      </Button>
    </div>
  {:else}
    <div class="grid gap-3">
      {#each info.planets as p (p.name)}
        <div
          class="flex flex-col gap-3 p-4 rounded-xl border bg-card text-card-foreground shadow-sm"
        >
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-2 min-w-0">
              <Globe
                class={cn(
                  "h-5 w-5 shrink-0",
                  p.active ? "text-amber-500" : "text-muted-foreground",
                )}
              />
              <span class="font-mono font-bold truncate">{p.name}</span>
              {#if p.active}
                <span
                  class="bg-amber-500/20 text-amber-600 px-1.5 rounded text-[10px] font-semibold shrink-0"
                  >{$t("planets.inUse")}</span
                >
              {/if}
            </div>
            <div class="flex items-center gap-1 shrink-0">
              <Button
                variant="ghost"
                size="icon"
                class="h-8 w-8"
                title={$t("planets.view")}
                on:click={() => openEdit(p.name, true)}
              >
                <Eye class="h-4 w-4" />
              </Button>
              <Button
                variant="ghost"
                size="icon"
                class="h-8 w-8"
                title={$t("planets.edit")}
                on:click={() => openEdit(p.name, false)}
              >
                <Pencil class="h-4 w-4" />
              </Button>
              <Button
                variant="ghost"
                size="icon"
                class="h-8 w-8"
                title={$t("common.copy")}
                on:click={() => openCopy(p)}
              >
                <Copy class="h-4 w-4" />
              </Button>
              <Button
                variant="ghost"
                size="icon"
                class="h-8 w-8"
                title={$t("planets.delete.button")}
                on:click={() => handleDelete(p)}
              >
                <Trash2 class="h-4 w-4 text-destructive" />
              </Button>
            </div>
          </div>

          <div class="flex items-center justify-between text-xs text-muted-foreground">
            <span>{formatSize(p.size)} · {formatTime(p.mtime)}</span>
            {#if p.active}
              <span class="text-xs text-muted-foreground"
                >{$t("planets.status.currentNote")}</span
              >
            {:else if applyingName === p.name}
              <span class="flex items-center gap-1 text-xs text-muted-foreground">
                <Loader2 class="h-3 w-3 animate-spin" />
                {$t("planets.applying")}
              </span>
            {:else}
              <Button variant="secondary" size="sm" class="h-7 text-xs" on:click={() => handleApply(p)}>
                <Play class="h-3 w-3 mr-1" />
                {$t("planets.apply.button")}
              </Button>
            {/if}
          </div>
        </div>
      {/each}
    </div>
  {/if}
</div>

{#if editorOpen}
  <div
    class="fixed inset-0 bg-background/80 backdrop-blur-sm z-[100]"
    on:click={closeEditor}
    role="presentation"
  >
    <div
      class="fixed left-[50%] top-[50%] z-[101] grid w-full max-w-lg translate-x-[-50%] translate-y-[-50%] gap-4 border bg-card p-6 shadow-lg duration-200 sm:rounded-lg max-h-[85vh] overflow-y-auto"
      on:click|stopPropagation
      on:keydown|stopPropagation
      role="dialog"
      aria-modal="true"
      tabindex="-1"
    >
      <div class="flex flex-col space-y-1.5 text-center sm:text-left">
        <h2 class="text-lg font-semibold leading-none tracking-tight">
          {editorMode === "add"
            ? $t("planets.editor.addTitle")
            : editorMode === "edit"
              ? $t("planets.editor.editTitle")
              : $t("planets.editor.viewTitle")}
        </h2>
        <p class="text-sm text-muted-foreground">{$t("planets.editor.desc")}</p>
      </div>

      <div class="grid gap-2">
        <Label for="planet-name">{$t("planets.editor.name")}</Label>
        <Input
          id="planet-name"
          type="text"
          placeholder={$t("planets.editor.namePlaceholder")}
          value={editorName}
          disabled={editorMode === "view" || editorSaving}
          on:input={(e) =>
            (editorName = (e.target as HTMLInputElement).value)}
        />
        <Label for="planet-content">{$t("planets.editor.content")}</Label>
        <textarea
          id="planet-content"
          class="flex w-full min-h-[220px] rounded-md border border-input bg-transparent px-3 py-2 text-sm font-mono shadow-sm placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring disabled:cursor-not-allowed disabled:opacity-50"
          placeholder={$t("planets.editor.contentPlaceholder")}
          bind:value={editorContent}
          disabled={editorMode === "view" || editorSaving}
        ></textarea>
      </div>

      <div class="flex flex-col-reverse sm:flex-row sm:justify-end sm:space-x-2 gap-2">
        <Button variant="outline" on:click={closeEditor} disabled={editorSaving}>
          {$t("common.cancel")}
        </Button>
        {#if editorMode !== "view"}
          <Button on:click={saveEditor} disabled={editorSaving}>
            {editorSaving ? $t("common.saving") : $t("common.save")}
          </Button>
        {/if}
      </div>
    </div>
  </div>
{/if}

{#if copyOpen}
  <div
    class="fixed inset-0 bg-background/80 backdrop-blur-sm z-[100]"
    on:click={closeCopy}
    role="presentation"
  >
    <div
      class="fixed left-[50%] top-[50%] z-[101] grid w-full max-w-lg translate-x-[-50%] translate-y-[-50%] gap-4 border bg-card p-6 shadow-lg duration-200 sm:rounded-lg"
      on:click|stopPropagation
      on:keydown|stopPropagation
      role="dialog"
      aria-modal="true"
      tabindex="-1"
    >
      <div class="flex flex-col space-y-1.5 text-center sm:text-left">
        <h2 class="text-lg font-semibold leading-none tracking-tight">
          {$t("planets.copy.title")}
        </h2>
        <p class="text-sm text-muted-foreground">
          {$t("planets.copy.message", { values: { src: copySrc } })}
        </p>
      </div>
      <div class="grid gap-2">
        <Label for="planet-copy-name">{$t("planets.editor.name")}</Label>
        <Input
          id="planet-copy-name"
          type="text"
          placeholder={$t("planets.editor.namePlaceholder")}
          value={copyDst}
          disabled={copySaving}
          on:input={(e) => (copyDst = (e.target as HTMLInputElement).value)}
        />
      </div>
      <div class="flex flex-col-reverse sm:flex-row sm:justify-end sm:space-x-2 gap-2">
        <Button variant="outline" on:click={closeCopy} disabled={copySaving}>
          {$t("common.cancel")}
        </Button>
        <Button on:click={saveCopy} disabled={copySaving}>
          {copySaving ? $t("common.saving") : $t("common.copy")}
        </Button>
      </div>
    </div>
  </div>
{/if}
