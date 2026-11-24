import { common, bundleManager, Want, wantConstant } from '@kit.AbilityKit';
import { updateManager } from '@kit.AppGalleryKit';
import { BusinessError, request } from '@kit.BasicServicesKit';
import { fileIo, fileUri, hash as fileHash } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { preferences } from '@kit.ArkData';

const PREFS_NAME: string = 'collection_genie_settings';
const MANIFEST_URL_KEY: string = 'update_manifest_url';

export const DEFAULT_UPDATE_MANIFEST_URL: string =
  'https://cdn.jsdelivr.net/gh/yyj7315/collection-genie@latest/update-manifest.json';

export interface UpdateManifest {
  versionName: string;
  versionCode: number;
  downloadUrl: string;
  sha256: string;
  releaseNotes: string;
  publishedAt: string;
}

export interface DownloadedUpdate {
  filePath: string;
  fileName: string;
  sha256: string;
}

export interface AppGalleryUpdateResult {
  checked: boolean;
  updateAvailable: boolean;
  message: string;
}

export class UpdateService {
  static getCurrentVersionName(): string {
    try {
      const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      return info.versionName;
    } catch (error) {
      return '未知';
    }
  }

  static getCurrentVersionCode(): number {
    try {
      const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      return info.versionCode;
    } catch (error) {
      return 0;
    }
  }

  static async getManifestUrl(context: common.UIAbilityContext): Promise<string> {
    try {
      const store = await preferences.getPreferences(context, PREFS_NAME);
      const value = await store.get(MANIFEST_URL_KEY, DEFAULT_UPDATE_MANIFEST_URL);
      return typeof value === 'string' && value.trim().length > 0
        ? value.trim()
        : DEFAULT_UPDATE_MANIFEST_URL;
    } catch (error) {
      return DEFAULT_UPDATE_MANIFEST_URL;
    }
  }

  static async saveManifestUrl(context: common.UIAbilityContext, value: string): Promise<void> {
    const store = await preferences.getPreferences(context, PREFS_NAME);
    await store.put(MANIFEST_URL_KEY, value.trim());
    await store.flush();
  }

  static async checkAppGallery(context: common.UIAbilityContext): Promise<AppGalleryUpdateResult> {
    try {
      const result = await updateManager.checkAppUpdate(context);
      if (result.updateAvailable === updateManager.UpdateAvailableCode.LATER_VERSION_EXIST) {
        const dialogResult = await updateManager.showUpdateDialog(context);
        return {
          checked: true,
          updateAvailable: dialogResult === updateManager.ShowUpdateResultCode.SHOW_DIALOG_SUCCESS,
          message: dialogResult === updateManager.ShowUpdateResultCode.SHOW_DIALOG_SUCCESS
            ? '已打开应用市场更新界面'
            : '检测到新版本，但未能打开应用市场更新界面'
        };
      }
      return {
        checked: true,
        updateAvailable: false,
        message: '应用市场未发现更高版本'
      };
    } catch (error) {
      return {
        checked: false,
        updateAvailable: false,
        message: ''
      };
    }
  }

  static async fetchManifest(manifestUrl: string): Promise<UpdateManifest> {
    if (manifestUrl.trim().length === 0) {
      throw new Error('请先配置更新清单地址。');
    }
    const client = http.createHttp();
    try {
      try {
        const response = await client.request(manifestUrl, {
          method: http.RequestMethod.GET,
          expectDataType: http.HttpDataType.STRING,
          connectTimeout: 10000,
          readTimeout: 10000,
          header: {
            'Accept': 'application/json',
            'Cache-Control': 'no-cache'
          }
        });
        if (response.responseCode !== http.ResponseCode.OK || typeof response.result !== 'string') {
          throw new Error(`HTTP ${response.responseCode}`);
        }
        const manifest = JSON.parse(response.result) as UpdateManifest;
        UpdateService.validateManifest(manifest);
        return manifest;
      } catch (error) {
        const requestError = error as BusinessError;
        const detail = requestError.message.length > 0 ? requestError.message : String(error);
        throw new Error(`无法读取更新清单：${detail}`);
      }
    } finally {
      client.destroy();
    }
  }

  static hasNewerVersion(manifest: UpdateManifest): boolean {
    const currentCode = UpdateService.getCurrentVersionCode();
    if (manifest.versionCode !== currentCode) {
      return manifest.versionCode > currentCode;
    }
    return UpdateService.compareVersionName(
      manifest.versionName,
      UpdateService.getCurrentVersionName()
    ) > 0;
  }

  static async downloadAndVerify(
    context: common.UIAbilityContext,
    manifest: UpdateManifest,
    onProgress: (received: number, total: number) => void
  ): Promise<DownloadedUpdate> {
    const directory = `${context.cacheDir}/updates`;
    if (!fileIo.accessSync(directory)) {
      fileIo.mkdirSync(directory, true);
    }
    const fileName = UpdateService.fileNameFromUrl(manifest.downloadUrl, manifest.versionName);
    const filePath = `${directory}/${fileName}`;
    if (fileIo.accessSync(filePath)) {
      fileIo.unlinkSync(filePath);
    }

    const task = await request.downloadFile(context, {
      url: manifest.downloadUrl,
      filePath: filePath,
      title: `收藏夹精灵 ${manifest.versionName}`,
      description: '下载并校验新版本',
      enableMetered: false,
      enableRoaming: false,
      background: false
    });

    await new Promise<void>((resolve: () => void, reject: (reason?: Object) => void) => {
      let settled = false;
      const timeoutId = setTimeout(() => {
        if (!settled) {
          settled = true;
          reject(new Error('升级包下载超时。'));
        }
      }, 120000);
      task.on('progress', (received: number, total: number) => {
        onProgress(received, total);
      });
      task.on('complete', () => {
        if (!settled) {
          settled = true;
          clearTimeout(timeoutId);
          resolve();
        }
      });
      task.on('fail', (errorCode: number) => {
        if (!settled) {
          settled = true;
          clearTimeout(timeoutId);
          reject(new Error(`升级包下载失败：${errorCode}`));
        }
      });
    });

    const actualSha256 = await fileHash.hash(filePath, 'sha256');
    if (actualSha256.toLowerCase() !== manifest.sha256.trim().toLowerCase()) {
      fileIo.unlinkSync(filePath);
      throw new Error('安装包 SHA-256 校验失败，文件已删除。');
    }
    return {
      filePath: filePath,
      fileName: fileName,
      sha256: actualSha256
    };
  }

  static async openInstallUi(context: common.UIAbilityContext, filePath: string): Promise<void> {
    const uri = fileUri.getUriFromPath(filePath);
    const want: Want = {
      action: 'ohos.want.action.viewData',
      uri: uri,
      type: 'application/vnd.harmonyos.hap',
      flags: wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION,
      parameters: {
        'ohos.extra.param.key.fileName': filePath.split('/').pop() ?? 'collection-genie-update.hap'
      }
    };
    await context.startAbility(want);
  }

  private static validateManifest(manifest: UpdateManifest): void {
    if (
      !manifest ||
      typeof manifest.versionName !== 'string' ||
      typeof manifest.versionCode !== 'number' ||
      typeof manifest.downloadUrl !== 'string' ||
      !manifest.downloadUrl.startsWith('https://') ||
      typeof manifest.sha256 !== 'string' ||
      manifest.sha256.length !== 64
    ) {
      throw new Error('更新清单字段不完整，已停止升级。');
    }
  }

  private static fileNameFromUrl(url: string, versionName: string): string {
    const cleanUrl = url.split('?')[0];
    const detected = cleanUrl.substring(cleanUrl.lastIndexOf('/') + 1);
    return detected.endsWith('.hap')
      ? detected
      : `collection-genie-${versionName}.hap`;
  }

  private static compareVersionName(left: string, right: string): number {
    const leftParts = left.split('.');
    const rightParts = right.split('.');
    const count = Math.max(leftParts.length, rightParts.length);
    for (let index = 0; index < count; index++) {
      const leftValue = Number.parseInt(leftParts[index] ?? '0');
      const rightValue = Number.parseInt(rightParts[index] ?? '0');
      if (leftValue !== rightValue) {
        return leftValue - rightValue;
      }
    }
    return 0;
  }
}
