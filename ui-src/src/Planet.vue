<template>
  <van-cell-group inset>
    <van-cell center :title="t('planet.usingTitle')"
      :value="usingCustom ? t('planet.usingCustom') : t('planet.usingDefault')">
      <template #right-icon>
        <van-button v-if="usingCustom" size="small" plain type="warning" style="margin-left: 8px"
          @click="restorePlanet">{{ t('planet.restore') }}</van-button>
      </template>
    </van-cell>
    <van-cell v-if="worldId" :title="t('planet.worldId')" :value="worldId" />
  </van-cell-group>

  <van-cell-group inset style="margin-top: 12px">
    <van-cell :title="t('planet.planetList')">
      <template #right-icon>
        <van-button size="small" type="primary" @click="openAdd">{{ t('planet.add') }}</van-button>
      </template>
    </van-cell>

    <van-empty v-if="planets.length == 0" :description="t('planet.noPlanets')" />

    <van-swipe-cell v-for="p in planets" :key="p.name">
      <van-cell :title="p.name" :label="planetMeta(p)">
        <template #right-icon>
          <van-tag v-if="p.active" type="warning" style="margin-right: 8px">{{ t('planet.inUse') }}</van-tag>
          <van-button v-if="!p.active" size="small" type="success" @click.stop="applyPlanet(p)">{{ t('planet.apply')
          }}</van-button>
        </template>
      </van-cell>
      <template #right>
        <van-button square type="primary" text="编辑" style="height: 100%; width: 60px" @click="openEdit(p, false)" />
        <van-button square type="default" :text="t('common.copy')" style="height: 100%; width: 60px"
          @click="openCopy(p)" />
        <van-button square type="danger" :text="t('common.delete')" style="height: 100%; width: 60px"
          @click="deletePlanet(p)" />
      </template>
    </van-swipe-cell>
  </van-cell-group>

  <!-- add / edit / view editor -->
  <van-popup v-model:show="editorShow" round :style="{ width: '92%', maxHeight: '88%' }" close-on-popstate>
    <div style="padding: 16px">
      <div style="font-weight: bold; margin-bottom: 12px">{{ editorTitle }}</div>
      <van-field v-model="editorName" :label="t('planet.name')" :placeholder="t('planet.namePlaceholder')"
        :readonly="editorMode === 'view'" :disabled="editorSaving" />
      <div style="font-size: 12px; color: #999; margin: 8px 0 4px">{{ t('planet.content') }}</div>
      <textarea v-model="editorContent" :readonly="editorMode === 'view' || editorSaving"
        :placeholder="t('planet.contentPlaceholder')"
        style="width: 100%; min-height: 220px; border: 1px solid #e5e5e5; border-radius: 8px; padding: 8px; font-family: monospace; font-size: 12px; background: transparent; color: inherit"></textarea>
      <div style="display: flex; justify-content: flex-end; gap: 8px; margin-top: 12px">
        <van-button size="small" @click="editorShow = false">{{ t('planet.cancel') }}</van-button>
        <van-button v-if="editorMode !== 'view'" size="small" type="primary" :loading="editorSaving"
          @click="saveEditor">{{ t('planet.save') }}</van-button>
      </div>
    </div>
  </van-popup>

  <!-- copy dialog -->
  <van-dialog v-model:show="copyShow" :title="t('planet.copyTitle')" show-cancel-button :before-close="saveCopy">
    <van-field v-model="copyDst" :label="t('planet.name')" :placeholder="t('planet.namePlaceholder')" />
  </van-dialog>
</template>

<script setup>
import { MODDIR, execCmd } from './tools'
import { useI18n } from './locales'
import { showConfirmDialog, showToast } from 'vant'

const { t } = useI18n()

const planets = ref([])
const usingCustom = ref(false)
const worldId = ref('')
const loading = ref(false)

const editorShow = ref(false)
const editorMode = ref('add') // add | edit | view
const editorName = ref('')
const editorNameOriginal = ref('')
const editorContent = ref('')
const editorSaving = ref(false)

const copyShow = ref(false)
const copySrc = ref('')
const copyDst = ref('')

const editorTitle = computed(() => {
  if (editorMode.value === 'add') return t('planet.editorAdd')
  if (editorMode.value === 'edit') return t('planet.editorEdit')
  return t('planet.editorView')
})

const planetMeta = (p) => {
  const size = p.size < 1024 ? `${p.size} B` : `${(p.size / 1024).toFixed(1)} KB`
  const time = p.mtime ? new Date(p.mtime * 1000).toLocaleString() : ''
  return `${size} · ${time}`
}

const loadPlanets = async () => {
  loading.value = true
  try {
    const res = await execCmd(`sh ${MODDIR}/api.sh planet list`)
    const info = JSON.parse(res || '{}')
    planets.value = Array.isArray(info.planets) ? info.planets : []
    usingCustom.value = info.usingCustom === true || info.usingCustom === 'true'
    worldId.value = info.worldId || ''
  } catch (e) {
    console.error(e)
    showToast(t('planet.loadFailed'))
  } finally {
    loading.value = false
  }
}

const validName = (name) => {
  if (!name || name.length === 0) {
    showToast(t('planet.nameRequired'))
    return false
  }
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(name)) {
    showToast(t('planet.nameInvalid'))
    return false
  }
  return true
}

const openAdd = () => {
  editorMode.value = 'add'
  editorName.value = ''
  editorNameOriginal.value = ''
  editorContent.value = ''
  editorShow.value = true
}

const openEdit = async (p, viewOnly) => {
  try {
    const b64 = await execCmd(`sh ${MODDIR}/api.sh planet show ${p.name}`)
    editorMode.value = viewOnly ? 'view' : 'edit'
    editorName.value = p.name
    editorNameOriginal.value = p.name
    editorContent.value = decodeURIComponent(escape(atob(String(b64 || '').replace(/\s+/g, ''))))
    editorShow.value = true
  } catch (e) {
    console.error(e)
    showToast(t('planet.showFailed'))
  }
}

const saveEditor = async () => {
  const name = editorName.value.trim()
  if (!validName(name)) return
  if (editorMode.value === 'add' && planets.value.some((p) => p.name === name)) {
    showToast(t('planet.nameExists'))
    return
  }
  editorSaving.value = true
  try {
    const b64 = btoa(unescape(encodeURIComponent(editorContent.value)))
    if (editorMode.value === 'add') {
      await execCmd(`sh ${MODDIR}/api.sh planet add ${name} '${b64}'`)
    } else if (editorMode.value === 'edit') {
      if (name !== editorNameOriginal.value) {
        await execCmd(`sh ${MODDIR}/api.sh planet copy ${editorNameOriginal.value} ${name}`)
        await execCmd(`sh ${MODDIR}/api.sh planet delete ${editorNameOriginal.value}`)
      }
      await execCmd(`sh ${MODDIR}/api.sh planet edit ${name} '${b64}'`)
    }
    editorShow.value = false
    showToast(t('planet.saveSuccess'))
    await loadPlanets()
  } catch (e) {
    console.error(e)
    showToast(t('planet.saveFailed'))
  } finally {
    editorSaving.value = false
  }
}

const openCopy = (p) => {
  copySrc.value = p.name
  copyDst.value = `${p.name}-copy`
  copyShow.value = true
}

const saveCopy = async (action) => {
  if (action !== 'confirm') return true
  const dst = copyDst.value.trim()
  if (!validName(dst)) return false
  if (planets.value.some((p) => p.name === dst)) {
    showToast(t('planet.nameExists'))
    return false
  }
  try {
    await execCmd(`sh ${MODDIR}/api.sh planet copy ${copySrc.value} ${dst}`)
    showToast(t('planet.copySuccess'))
    copyShow.value = false
    await loadPlanets()
    return true
  } catch (e) {
    console.error(e)
    showToast(t('planet.saveFailed'))
    return false
  }
}

const applyPlanet = (p) => {
  showConfirmDialog({
    title: t('planet.applyTitle'),
    message: t('planet.applyMessage').replace('{name}', p.name),
  }).then(async () => {
    try {
      await execCmd(`sh ${MODDIR}/api.sh planet apply ${p.name}`)
      showToast(t('planet.applySuccess'))
      await loadPlanets()
    } catch (e) {
      console.error(e)
      showToast(t('planet.applyFailed'))
    }
  }).catch(() => { })
}

const restorePlanet = () => {
  showConfirmDialog({
    title: t('planet.restoreTitle'),
    message: t('planet.restoreMessage'),
  }).then(async () => {
    try {
      await execCmd(`sh ${MODDIR}/api.sh planet restore`)
      showToast(t('planet.restoreSuccess'))
      await loadPlanets()
    } catch (e) {
      console.error(e)
      showToast(t('planet.restoreFailed'))
    }
  }).catch(() => { })
}

const deletePlanet = (p) => {
  showConfirmDialog({
    title: t('planet.deleteTitle'),
    message: t('planet.deleteMessage').replace('{name}', p.name),
  }).then(async () => {
    try {
      await execCmd(`sh ${MODDIR}/api.sh planet delete ${p.name}`)
      showToast(t('planet.deleteSuccess'))
      await loadPlanets()
    } catch (e) {
      console.error(e)
      showToast(t('planet.deleteFailed'))
    }
  }).catch(() => { })
}

loadPlanets()
</script>
