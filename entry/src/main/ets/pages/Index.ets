import { common } from '@kit.AbilityKit';
import { promptAction, window } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { detectBarcode, scanBarcode, scanCore } from '@kit.ScanKit';
import {
  AddCollectionResult,
  CollectionItem,
  CollectionRepository
} from '../data/CollectionRepository';
import {
  UpdateManifest,
  UpdateService
} from '../data/UpdateService';

@Component
struct MetricCardView {
  @Prop label: string;
  @Prop value: string;
  @Prop color: string;

  build() {
    Column({ space: 5 }) {
      Text(this.value)
        .fontSize(27)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.color)
      Text(this.label)
        .fontSize(13)
        .fontColor('#64766F')
    }
    .layoutWeight(1)
    .padding({ top: 16, bottom: 16 })
    .backgroundColor('#FFFFFF')
    .borderRadius(16)
  }
}

@Entry
@Component
struct Index {
  private repository: CollectionRepository = CollectionRepository.getInstance();
  private initialized: boolean = false;
  private lastConsumedShareSignal: number = 0;
  private detailDeleteArmed: boolean = false;

  @StorageLink('shareSignal')
  @Watch('onShareSignalChanged')
  shareSignal: number = 0;
  @StorageProp('shareTestResult') shareTestResult: string = '';

  @State activeTab: number = 0;
  @State items: CollectionItem[] = [];
  @State categories: string[] = ['全部'];
  @State editableCategories: string[] = [];
  @State searchText: string = '';
  @State newCategoryName: string = '';
  @State selectedCategory: string = '全部';
  @State selectedItem: CollectionItem | null = null;
  @State shareNotice: string = '';
  @State shareNoticeSuccess: boolean = true;
  @State quickActionBusy: boolean = false;
  @State loading: boolean = true;
  @State bottomSafeInset: number = 40;
  @State currentVersion: string = '0.4.2';
  @State updateManifestUrl: string = '';
  @State updateBusy: boolean = false;
  @State updateAvailable: boolean = false;
  @State updateVersionName: string = '';
  @State updateDownloadUrl: string = '';
  @State updateSha256: string = '';
  @State updateReleaseNotes: string = '';
  @State updateStatus: string = '';
  @State updateStatusSuccess: boolean = true;

  aboutToAppear(): void {
    this.initialize();
  }

  onPageShow(): void {
    if (this.initialized) {
      this.refreshForForeground();
      this.consumePendingShare();
    }
  }

  private async initialize(): Promise<void> {
    if (this.initialized) {
      return;
    }
    try {
      const context = getContext(this) as common.UIAbilityContext;
      await this.updateBottomSafeInset(context);
      await this.repository.initialize(context);
      this.currentVersion = UpdateService.getCurrentVersionName();
      this.updateManifestUrl = await UpdateService.getManifestUrl(context);
      this.initialized = true;
      await this.refreshItems();
      this.consumePendingShare();
    } catch (error) {
      this.loading = false;
      this.shareNoticeSuccess = false;
      this.shareNotice = `本地数据初始化失败：${String(error)}`;
    }
  }

  private async updateBottomSafeInset(context: common.UIAbilityContext): Promise<void> {
    try {
      const mainWindow = await window.getLastWindow(context);
      const systemArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const indicatorArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      const systemHeight = systemArea.visible ? systemArea.bottomRect.height : 0;
      const indicatorHeight = indicatorArea.visible ? indicatorArea.bottomRect.height : 0;
      const bottomHeight = Math.max(systemHeight, indicatorHeight);
      this.bottomSafeInset = Math.min(56, Math.max(40, Math.ceil(px2vp(bottomHeight)) + 10));
    } catch (error) {
      this.bottomSafeInset = 40;
    }
  }

  onShareSignalChanged(): void {
    if (this.initialized) {
      this.consumePendingShare();
    }
  }

  private async consumePendingShare(): Promise<void> {
    const signal = AppStorage.get<number>('shareSignal') ?? 0;
    if (signal <= this.lastConsumedShareSignal) {
      return;
    }
    this.lastConsumedShareSignal = signal;
    const payload = AppStorage.get<string>('pendingSharePayloadText') ?? '';
    if (payload.length === 0) {
      return;
    }
    AppStorage.setOrCreate('pendingSharePayloadText', '');
    await this.savePayload(payload, '分享内容');
  }

  private async refreshItems(): Promise<void> {
    this.items = await this.repository.getAll();
    this.editableCategories = await this.repository.getCategories();
    const allCategories: string[] = ['全部'];
    for (let index = 0; index < this.editableCategories.length; index++) {
      allCategories.push(this.editableCategories[index]);
    }
    this.categories = allCategories;
    if (!this.categories.includes(this.selectedCategory)) {
      this.selectedCategory = '全部';
    }
    this.loading = false;
    if (this.selectedItem !== null) {
      this.selectedItem = await this.repository.findById(this.selectedItem.id);
    }
  }

  private async savePayload(payload: string, origin: string): Promise<void> {
    try {
      const result: AddCollectionResult = await this.repository.addFromShare(payload);
      await this.refreshItems();
      this.activeTab = 1;
      this.shareNoticeSuccess = true;
      this.shareNotice = result.created
        ? `已从${origin}收录到「${result.category}」`
        : `这条内容已经收藏过，本次记录次数已累计`;
      this.selectedItem = null;
    } catch (error) {
      this.shareNoticeSuccess = false;
      this.shareNotice = `${origin}收录失败：${String(error)}`;
    }
  }

  private async collectFromClipboard(): Promise<void> {
    if (this.quickActionBusy) {
      return;
    }
    this.quickActionBusy = true;
    try {
      const board = pasteboard.getSystemPasteboard();
      const hasData = await board.hasData();
      if (!hasData) {
        this.shareNoticeSuccess = false;
        this.shareNotice = '剪贴板为空，请先复制视频分享文字或链接。';
        return;
      }
      const data = await board.getData();
      const text = data.getPrimaryText().trim();
      if (text.length === 0) {
        this.shareNoticeSuccess = false;
        this.shareNotice = '剪贴板里没有可收录的文本。';
        return;
      }
      if (this.extractHttpUrl(text).length === 0) {
        this.shareNoticeSuccess = false;
        this.shareNotice = '没有在剪贴板中找到 http(s) 链接，请复制完整的分享文字后再试。';
        return;
      }
      await this.savePayload(text, '剪贴板');
    } catch (error) {
      this.shareNoticeSuccess = false;
      this.shareNotice = `读取剪贴板失败：${String(error)}`;
    } finally {
      this.quickActionBusy = false;
    }
  }

  private async collectFromScreenshotQRCode(): Promise<void> {
    if (this.quickActionBusy) {
      return;
    }
    this.quickActionBusy = true;
    this.shareNotice = '';
    try {
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      const picker = new photoAccessHelper.PhotoViewPicker();
      const selected = await picker.select(options);
      if (selected.photoUris.length === 0) {
        return;
      }
      const scanOptions: scanBarcode.ScanOptions = {
        scanTypes: [scanCore.ScanType.QR_CODE]
      };
      const results = await detectBarcode.decode(
        { uri: selected.photoUris[0] },
        scanOptions
      );
      let payload = '';
      for (let index = 0; index < results.length; index++) {
        payload = this.extractHttpUrl(results[index].originalValue);
        if (payload.length > 0) {
          break;
        }
      }
      if (payload.length === 0) {
        this.shareNoticeSuccess = false;
        this.shareNotice = '图片中没有识别到包含网址的二维码。';
        return;
      }
      await this.savePayload(payload, '截图二维码');
    } catch (error) {
      this.shareNoticeSuccess = false;
      this.shareNotice = `截图二维码识别失败：${String(error)}`;
    } finally {
      this.quickActionBusy = false;
    }
  }

  private extractHttpUrl(value: string): string {
    const match: RegExpMatchArray | null = value.match(/https?:\/\/[^\s，。！？；;]+/i);
    if (match === null) {
      return '';
    }
    let url = match[0].trim();
    while (url.length > 0 && '.,!?;:，。！？；：）)】]'.includes(url.charAt(url.length - 1))) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  private async createCategory(): Promise<void> {
    try {
      const created = await this.repository.addCategory(this.newCategoryName);
      this.newCategoryName = '';
      await this.refreshItems();
      this.selectedCategory = created;
      this.activeTab = 1;
      this.shareNoticeSuccess = true;
      this.shareNotice = `已新增归类「${created}」，可在内容详情中选择它。`;
    } catch (error) {
      promptAction.showToast({ message: String(error) });
    }
  }

  private async refreshForForeground(): Promise<void> {
    const selectedId = this.selectedItem === null ? 0 : this.selectedItem.id;
    this.selectedItem = null;
    await this.refreshItems();
    if (selectedId > 0) {
      this.selectedItem = await this.repository.findById(selectedId);
    }
  }

  private async saveUpdateManifestUrl(): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    try {
      await UpdateService.saveManifestUrl(context, this.updateManifestUrl);
      this.updateStatusSuccess = true;
      this.updateStatus = '更新清单地址已保存。';
    } catch (error) {
      this.updateStatusSuccess = false;
      this.updateStatus = `更新地址保存失败：${String(error)}`;
    }
  }

  private async checkForUpdates(): Promise<void> {
    if (this.updateBusy) {
      return;
    }
    this.updateBusy = true;
    this.updateAvailable = false;
    this.updateStatus = '正在检查新版本…';
    this.updateStatusSuccess = true;
    const context = getContext(this) as common.UIAbilityContext;
    try {
      const appGalleryResult = await UpdateService.checkAppGallery(context);
      if (appGalleryResult.updateAvailable) {
        this.updateStatusSuccess = true;
        this.updateStatus = appGalleryResult.message;
        return;
      }

      const manifest = await UpdateService.fetchManifest(this.updateManifestUrl);
      if (!UpdateService.hasNewerVersion(manifest)) {
        this.updateStatusSuccess = true;
        this.updateStatus = `当前已是最新版本 v${this.currentVersion}`;
        return;
      }
      this.updateAvailable = true;
      this.updateVersionName = manifest.versionName;
      this.updateDownloadUrl = manifest.downloadUrl;
      this.updateSha256 = manifest.sha256;
      this.updateReleaseNotes = manifest.releaseNotes;
      this.updateStatusSuccess = true;
      this.updateStatus = `发现新版本 v${manifest.versionName}`;
    } catch (error) {
      this.updateStatusSuccess = false;
      this.updateStatus = `检查更新失败：${String(error)}`;
    } finally {
      this.updateBusy = false;
    }
  }

  private async downloadUpdate(): Promise<void> {
    if (this.updateBusy || !this.updateAvailable) {
      return;
    }
    this.updateBusy = true;
    this.updateStatusSuccess = true;
    this.updateStatus = '正在下载升级包…';
    const context = getContext(this) as common.UIAbilityContext;
    const manifest: UpdateManifest = {
      versionName: this.updateVersionName,
      versionCode: 0,
      downloadUrl: this.updateDownloadUrl,
      sha256: this.updateSha256,
      releaseNotes: this.updateReleaseNotes,
      publishedAt: ''
    };
    try {
      const downloaded = await UpdateService.downloadAndVerify(
        context,
        manifest,
        (received: number, total: number) => {
          if (total > 0) {
            const percent = Math.min(99, Math.floor(received * 100 / total));
            this.updateStatus = `正在下载升级包…${percent}%`;
          }
        }
      );
      this.updateStatus = `SHA-256 校验通过，正在打开系统安装界面…`;
      await UpdateService.openInstallUi(context, downloaded.filePath);
      this.updateStatusSuccess = true;
      this.updateStatus = '升级包已校验，请在系统界面确认安装。';
    } catch (error) {
      this.updateStatusSuccess = false;
      this.updateStatus = `升级失败：${String(error)}`;
    } finally {
      this.updateBusy = false;
    }
  }

  private async reloadSelectedItem(id: number): Promise<void> {
    this.selectedItem = null;
    await this.refreshItems();
    this.selectedItem = await this.repository.findById(id);
  }

  private filteredItems(): CollectionItem[] {
    const keyword = this.searchText.trim().toLowerCase();
    return this.items.filter((item: CollectionItem) => {
      const categoryMatched = this.selectedCategory === '全部' ||
        item.category === this.selectedCategory;
      if (!categoryMatched) {
        return false;
      }
      if (keyword.length === 0) {
        return true;
      }
      return item.title.toLowerCase().includes(keyword) ||
        item.tags.toLowerCase().includes(keyword) ||
        item.notes.toLowerCase().includes(keyword) ||
        item.author.toLowerCase().includes(keyword);
    });
  }

  private categoryCount(category: string): number {
    return this.items.filter((item: CollectionItem) => item.category === category).length;
  }

  private statusCount(status: string): number {
    return this.items.filter((item: CollectionItem) => item.status === status).length;
  }

  private duplicateCount(): number {
    return this.items.filter((item: CollectionItem) => item.share_count > 1).length;
  }

  private staleCount(): number {
    const threshold = Date.now() - 30 * 24 * 60 * 60 * 1000;
    return this.items.filter((item: CollectionItem) =>
      item.status !== '已完成' &&
      item.last_opened_time === 0 &&
      item.collect_time < threshold
    ).length;
  }

  private recentItems(): CollectionItem[] {
    return this.items.slice(0, 4);
  }

  private reviewItem(): CollectionItem | null {
    if (this.items.length === 0) {
      return null;
    }
    const unread = this.items.filter((item: CollectionItem) => item.status === '未看');
    const pool = unread.length > 0 ? unread : this.items;
    return pool[Math.floor(Date.now() / 60000) % pool.length];
  }

  private openDetail(item: CollectionItem): void {
    this.detailDeleteArmed = false;
    this.selectedItem = item;
  }

  private closeDetail(): void {
    this.detailDeleteArmed = false;
    this.selectedItem = null;
  }

  private async openOriginal(item: CollectionItem): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      await context.openLink(item.canonical_url);
      await this.repository.recordOpen(item.id);
      await this.refreshItems();
    } catch (error) {
      promptAction.showToast({ message: `无法打开原链接：${String(error)}` });
    }
  }

  private async copyLink(item: CollectionItem): Promise<void> {
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, item.original_url);
      await pasteboard.getSystemPasteboard().setData(data);
      promptAction.showToast({ message: '链接已复制' });
    } catch (error) {
      promptAction.showToast({ message: `复制失败：${String(error)}` });
    }
  }

  private async setStatus(item: CollectionItem, status: string): Promise<void> {
    await this.repository.updateStatus(item.id, status);
    await this.reloadSelectedItem(item.id);
  }

  private async setCategory(item: CollectionItem, category: string): Promise<void> {
    await this.repository.updateCategory(item.id, category);
    await this.reloadSelectedItem(item.id);
  }

  private async saveNotes(item: CollectionItem): Promise<void> {
    await this.repository.updateNotes(item.id, item.notes);
    promptAction.showToast({ message: '笔记已保存' });
    await this.reloadSelectedItem(item.id);
  }

  private async deleteCurrent(): Promise<void> {
    if (this.selectedItem === null) {
      return;
    }
    if (!this.detailDeleteArmed) {
      this.detailDeleteArmed = true;
      promptAction.showToast({ message: '再次点击即可删除本应用记录' });
      return;
    }
    await this.repository.deleteById(this.selectedItem.id);
    this.closeDetail();
    await this.refreshItems();
  }

  private formatDate(timestamp: number): string {
    if (timestamp <= 0) {
      return '尚未打开';
    }
    const date = new Date(timestamp);
    const month = (date.getMonth() + 1).toString().padStart(2, '0');
    const day = date.getDate().toString().padStart(2, '0');
    return `${month}-${day}`;
  }

  private categoryColor(category: string): string {
    switch (category) {
      case '健康运动':
        return '#0A8F71';
      case '学习成长':
        return '#3579D1';
      case '科技数码':
        return '#6558C9';
      case '影视娱乐':
        return '#C25A75';
      case '生活方式':
        return '#A36A31';
      case '美食':
        return '#D06C2B';
      case '旅行':
        return '#2C879A';
      default:
        return '#6C7A76';
    }
  }

  private categoryIcon(category: string): string {
    switch (category) {
      case '健康运动':
        return '动';
      case '学习成长':
        return '学';
      case '科技数码':
        return '科';
      case '影视娱乐':
        return '影';
      case '生活方式':
        return '生';
      case '美食':
        return '食';
      case '旅行':
        return '旅';
      default:
        return '收';
    }
  }

  @Builder
  private SectionTitle(title: string, subtitle: string) {
    Column({ space: 3 }) {
      Text(title)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor('#173B34')
      if (subtitle.length > 0) {
        Text(subtitle)
          .fontSize(13)
          .fontColor('#74857F')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private CollectionCard(item: CollectionItem, compact: boolean = false) {
    Column({ space: 10 }) {
      Row() {
        Row({ space: 8 }) {
          Text(this.categoryIcon(item.category))
            .width(32)
            .height(32)
            .textAlign(TextAlign.Center)
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
            .backgroundColor(this.categoryColor(item.category))
            .borderRadius(10)
          Column({ space: 2 }) {
            Text(item.category)
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.categoryColor(item.category))
            Text(item.source)
              .fontSize(11)
              .fontColor('#84928E')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(HorizontalAlign.Start)
        }
        Blank()
        if (item.share_count > 1) {
          Text(`分享 ${item.share_count} 次`)
            .fontSize(11)
            .fontColor('#8A6420')
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .backgroundColor('#FFF3D4')
            .borderRadius(10)
        }
      }
      .width('100%')

      Text(item.title)
        .fontSize(compact ? 16 : 17)
        .fontWeight(FontWeight.Medium)
        .fontColor('#213B35')
        .lineHeight(24)
        .maxLines(compact ? 2 : 3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      Row({ space: 10 }) {
        Text(item.status)
          .fontSize(12)
          .fontColor(item.status === '已完成' ? '#087A5F' : '#62736E')
        Text(`打开 ${item.open_count} 次`)
          .fontSize(12)
          .fontColor('#84928E')
        if (item.last_opened_time > 0) {
          Text(`最近 ${this.formatDate(item.last_opened_time)}`)
            .fontSize(12)
            .fontColor('#84928E')
        }
        Blank()
        Text(this.formatDate(item.collect_time))
          .fontSize(12)
          .fontColor('#9AA6A2')
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#FFFFFF')
    .borderRadius(17)
    .onClick(() => {
      this.openDetail(item);
    })
  }

  @Builder
  private EmptyState(title: string, description: string) {
    Column({ space: 10 }) {
      Text('+')
        .fontSize(40)
        .fontColor('#B8C8C2')
      Text(title)
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor('#40544F')
      Text(description)
        .fontSize(14)
        .lineHeight(22)
        .fontColor('#7A8B86')
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({ top: 42, bottom: 42, left: 26, right: 26 })
    .backgroundColor('#FFFFFF')
    .borderRadius(18)
  }

  @Builder
  private HomePage() {
    Scroll() {
      Column({ space: 16 }) {
        Column({ space: 6 }) {
          Text('收藏夹精灵')
            .fontSize(30)
            .fontWeight(FontWeight.Bold)
            .fontColor('#173B34')
          Text('把刷到的好内容，重新变成看得见、找得到、看得完的收藏。')
            .fontSize(14)
            .lineHeight(22)
            .fontColor('#667B75')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ top: 14 })

        Row({ space: 10 }) {
          MetricCardView({ label: '总收藏', value: this.items.length.toString(), color: '#0B8268' })
          MetricCardView({
            label: '未完成',
            value: (this.items.length - this.statusCount('已完成')).toString(),
            color: '#A2691E'
          })
          MetricCardView({ label: '重复分享', value: this.duplicateCount().toString(), color: '#5A64B5' })
        }
        .width('100%')

        Column({ space: 12 }) {
          Row() {
            Column({ space: 3 }) {
              Text('快捷收录')
                .fontSize(20)
                .fontWeight(FontWeight.Bold)
                .fontColor('#173B34')
              Text('不用切换分享面板，复制链接或选一张截图即可')
                .fontSize(13)
                .fontColor('#74857F')
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Text('本地处理')
              .fontSize(11)
              .fontColor('#0B8268')
              .padding({ left: 9, right: 9, top: 5, bottom: 5 })
              .backgroundColor('#E1F5ED')
              .borderRadius(11)
          }
          .width('100%')

          Row({ space: 10 }) {
            PasteButton({
              icon: PasteIconStyle.LINES,
              text: PasteDescription.PASTE,
              buttonType: ButtonType.Capsule
            })
              .width('48%')
              .height(46)
              .fontSize(14)
              .backgroundColor('#168F77')
              .fontColor('#FFFFFF')
              .enabled(!this.quickActionBusy)
              .onClick((event: ClickEvent, result: PasteButtonOnClickResult) => {
                if (result === PasteButtonOnClickResult.SUCCESS) {
                  this.collectFromClipboard();
                } else {
                  this.shareNoticeSuccess = false;
                  this.shareNotice = '系统未授予本次剪贴板读取权限。';
                }
              })
            Button('识别截图二维码')
              .layoutWeight(1)
              .height(46)
              .fontSize(14)
              .backgroundColor('#E5F1ED')
              .fontColor('#126B59')
              .enabled(!this.quickActionBusy)
              .opacity(this.quickActionBusy ? 0.6 : 1)
              .onClick(() => {
                this.collectFromScreenshotQRCode();
              })
          }
          .width('100%')

          Text('只在你点击按钮时读取剪贴板或选择图片；不会在后台自动读取。')
            .fontSize(11)
            .lineHeight(17)
            .fontColor('#7A8B86')
            .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(16)
        .backgroundColor('#FFFFFF')
        .borderRadius(18)

        if (this.shareNotice.length > 0) {
          Row({ space: 10 }) {
            Text(this.shareNoticeSuccess ? '✓' : '!')
              .width(26)
              .height(26)
              .textAlign(TextAlign.Center)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.shareNoticeSuccess ? '#087A5F' : '#A33D32')
              .backgroundColor(this.shareNoticeSuccess ? '#DDF4EC' : '#FBE7E3')
              .borderRadius(13)
            Text(this.shareNotice)
              .fontSize(14)
              .fontColor(this.shareNoticeSuccess ? '#125D4C' : '#8E352C')
              .layoutWeight(1)
          }
          .width('100%')
          .padding(14)
          .backgroundColor(this.shareNoticeSuccess ? '#EAF8F3' : '#FFF0ED')
          .borderRadius(14)
        }

        Column({ space: 12 }) {
          this.SectionTitle('今天回看一条', '从收藏里挑一条，别只是存起来')
          if (this.reviewItem() !== null) {
            this.CollectionCard(this.reviewItem() as CollectionItem, true)
          } else {
            this.EmptyState('还没有收藏', '在支持的应用中点击分享，再选择收藏夹精灵即可开始收录。')
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        Column({ space: 12 }) {
          Row() {
            Column({ space: 3 }) {
              Text('最近收录')
                .fontSize(20)
                .fontWeight(FontWeight.Bold)
                .fontColor('#173B34')
              Text('最新进入收藏库的内容')
                .fontSize(13)
                .fontColor('#74857F')
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Text('查看全部')
              .fontSize(13)
              .fontColor('#0B8268')
              .onClick(() => {
                this.activeTab = 1;
                this.selectedCategory = '全部';
              })
          }
          .width('100%')

          ForEach(this.recentItems(), (item: CollectionItem) => {
            this.CollectionCard(item, true)
          }, (item: CollectionItem) => item.id.toString())
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ bottom: 18 })
      }
      .padding({ left: 16, right: 16 })
      .width('100%')
    }
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }

  @Builder
  private LibraryPage() {
    Column({ space: 12 }) {
      Row() {
        Column({ space: 3 }) {
          Text('内容库')
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor('#173B34')
          Text(`${this.filteredItems().length} 条结果`)
            .fontSize(13)
            .fontColor('#74857F')
        }
        .alignItems(HorizontalAlign.Start)
        Blank()
        Text('按时间')
          .fontSize(13)
          .fontColor('#0B8268')
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14 })

      TextInput({ placeholder: '搜索标题、作者、标签或笔记', text: this.searchText })
        .height(44)
        .fontSize(14)
        .backgroundColor('#FFFFFF')
        .borderRadius(13)
        .padding({ left: 14, right: 14 })
        .margin({ left: 16, right: 16 })
        .onChange((value: string) => {
          this.searchText = value;
        })

      Row({ space: 8 }) {
        TextInput({ placeholder: '新增自己的归类，例如「产品灵感」', text: this.newCategoryName })
          .layoutWeight(1)
          .height(40)
          .fontSize(13)
          .maxLength(16)
          .backgroundColor('#FFFFFF')
          .borderRadius(12)
          .onChange((value: string) => {
            this.newCategoryName = value;
          })
          .onSubmit(() => {
            this.createCategory();
          })
        Button('新增归类')
          .height(40)
          .fontSize(13)
          .backgroundColor('#E5F1ED')
          .fontColor('#126B59')
          .onClick(() => {
            this.createCategory();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16 })

      Scroll() {
        Row({ space: 8 }) {
          ForEach(this.categories, (category: string) => {
            Text(category === '全部' ? `全部 ${this.items.length}` : `${category} ${this.categoryCount(category)}`)
              .fontSize(13)
              .fontColor(this.selectedCategory === category ? '#FFFFFF' : '#4F625C')
              .padding({ left: 13, right: 13, top: 8, bottom: 8 })
              .backgroundColor(this.selectedCategory === category ? '#178F78' : '#FFFFFF')
              .borderRadius(16)
              .onClick(() => {
                this.selectedCategory = category;
              })
          }, (category: string) => category)
        }
        .padding({ left: 16, right: 16 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .height(38)

      Scroll() {
        Column({ space: 10 }) {
          if (this.loading) {
            LoadingProgress()
              .width(42)
              .height(42)
              .margin({ top: 60 })
          } else if (this.filteredItems().length === 0) {
            this.EmptyState(
              this.items.length === 0 ? '内容库还是空的' : '没有符合条件的内容',
              this.items.length === 0
                ? '从任意支持的应用分享一条内容到这里，系统会自动识别来源并分类保存。'
                : '试试更换分类或清空搜索关键词。'
            )
          } else {
            ForEach(this.filteredItems(), (item: CollectionItem) => {
              this.CollectionCard(item)
            }, (item: CollectionItem) => item.id.toString())
          }
        }
        .padding({ left: 16, right: 16, bottom: 18 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  private StatsPage() {
    Scroll() {
      Column({ space: 16 }) {
        Column() {
          this.SectionTitle('收藏概览', '用数据看见你的内容消费习惯')
        }
        .padding({ top: 14 })

        Row({ space: 10 }) {
          MetricCardView({
            label: '已打开',
            value: this.items.filter((item: CollectionItem) => item.open_count > 0).length.toString(),
            color: '#2674B8'
          })
          MetricCardView({ label: '已完成', value: this.statusCount('已完成').toString(), color: '#0B8268' })
          MetricCardView({ label: '待清理', value: this.staleCount().toString(), color: '#A2691E' })
        }
        .width('100%')

        Column({ space: 14 }) {
          this.SectionTitle('分类分布', '自动分类结果，可在详情页随时修改')
          ForEach(this.editableCategories, (category: string) => {
            Column({ space: 7 }) {
              Row() {
                Text(category)
                  .fontSize(14)
                  .fontColor('#344C46')
                Blank()
                Text(`${this.categoryCount(category)} 条`)
                  .fontSize(12)
                  .fontColor('#74857F')
              }
              .width('100%')
              Row() {
                Row()
                  .height(8)
                  .width(this.items.length === 0 ? '0%' : `${Math.max(4, Math.round(this.categoryCount(category) * 100 / this.items.length))}%`)
                  .backgroundColor(this.categoryColor(category))
                  .borderRadius(4)
              }
              .width('100%')
              .height(8)
              .backgroundColor('#ECF1EF')
              .borderRadius(4)
            }
            .width('100%')
          }, (category: string) => category)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(17)
        .backgroundColor('#FFFFFF')
        .borderRadius(18)

        Column({ space: 12 }) {
          this.SectionTitle('清理建议', '重复不等于无用，清理前请先确认')
          Row() {
            Text('30 天未打开')
              .fontSize(15)
              .fontColor('#344C46')
            Blank()
            Text(`${this.staleCount()} 条`)
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor('#A2691E')
          }
          .width('100%')
          Row() {
            Text('重复分享内容')
              .fontSize(15)
              .fontColor('#344C46')
            Blank()
            Text(`${this.duplicateCount()} 条`)
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor('#5A64B5')
          }
          .width('100%')
          Text('打开内容库中的「待整理」，逐个补充笔记、完成状态或归档。')
            .fontSize(13)
            .lineHeight(20)
            .fontColor('#74857F')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(17)
        .backgroundColor('#FFFFFF')
        .borderRadius(18)
        .margin({ bottom: 18 })
      }
      .padding({ left: 16, right: 16 })
      .width('100%')
    }
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }

  @Builder
  private SettingsPage() {
    Scroll() {
      Column({ space: 16 }) {
        Column() {
          this.SectionTitle('设置与说明', '当前版本为本地单用户 MVP')
        }
        .padding({ top: 14 })

        Column({ space: 12 }) {
          Row() {
            Text('版本升级')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor('#173B34')
            Blank()
            Text(`v${this.currentVersion}`)
              .fontSize(12)
              .fontColor('#0B8268')
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .backgroundColor('#E1F5ED')
              .borderRadius(12)
          }
          .width('100%')

          Text('更新清单地址')
            .fontSize(13)
            .fontColor('#60746E')
          TextInput({
            placeholder: 'https://example.com/update-manifest.json',
            text: this.updateManifestUrl
          })
            .height(42)
            .fontSize(12)
            .backgroundColor('#F2F6F4')
            .borderRadius(11)
            .onChange((value: string) => {
              this.updateManifestUrl = value;
            })

          Row({ space: 10 }) {
            Button('保存地址')
              .layoutWeight(1)
              .height(42)
              .fontSize(13)
              .backgroundColor('#E5F1ED')
              .fontColor('#126B59')
              .onClick(() => {
                this.saveUpdateManifestUrl();
              })
            Button(this.updateBusy ? '检查中…' : '检查更新')
              .layoutWeight(1)
              .height(42)
              .fontSize(13)
              .backgroundColor('#168F77')
              .fontColor('#FFFFFF')
              .enabled(!this.updateBusy)
              .opacity(this.updateBusy ? 0.6 : 1)
              .onClick(() => {
                this.checkForUpdates();
              })
          }
          .width('100%')

          if (this.updateAvailable) {
            Column({ space: 7 }) {
              Text(`发现新版本 v${this.updateVersionName}`)
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor('#173B34')
              Text(this.updateReleaseNotes.length > 0 ? this.updateReleaseNotes : '本次更新包含功能优化与问题修复。')
                .fontSize(13)
                .lineHeight(20)
                .fontColor('#5F706B')
              Button(this.updateBusy ? '下载校验中…' : '下载、校验并安装')
                .width('100%')
                .height(42)
                .fontSize(13)
                .backgroundColor('#0C8169')
                .fontColor('#FFFFFF')
                .enabled(!this.updateBusy)
                .onClick(() => {
                  this.downloadUpdate();
                })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding(12)
            .backgroundColor('#EFF8F4')
            .borderRadius(12)
          }

          if (this.updateStatus.length > 0) {
            Text(this.updateStatus)
              .fontSize(12)
              .lineHeight(18)
              .fontColor(this.updateStatusSuccess ? '#126B59' : '#9C4035')
              .width('100%')
              .padding(10)
              .backgroundColor(this.updateStatusSuccess ? '#E7F7F1' : '#FFF0ED')
              .borderRadius(10)
          }

          Text('安装包必须来自 HTTPS 地址并通过 SHA-256 校验；最终安装仍需用户在系统界面确认。')
            .fontSize(11)
            .lineHeight(17)
            .fontColor('#7A8B86')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(17)
        .backgroundColor('#FFFFFF')
        .borderRadius(18)

        Column({ space: 12 }) {
          Text('如何收录')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#173B34')
          Text('方式一：在抖音精选、哔哩哔哩、小红书等应用点击「分享 → 系统分享 → 收藏夹精灵」。')
            .fontSize(14)
            .lineHeight(21)
            .fontColor('#4B615B')
          Text('方式二：先复制视频分享文字或链接，回到首页点击「从剪贴板收录」。')
            .fontSize(14)
            .lineHeight(21)
            .fontColor('#4B615B')
          Text('方式三：保存带二维码的截图，在首页点击「识别截图二维码」并选择图片。')
            .fontSize(14)
            .lineHeight(21)
            .fontColor('#4B615B')
          Text('方式四（电脑/二合一设备）：在支持划词扩展的应用中选中文字，通过系统的划词菜单收藏。手机系统当前不开放这一入口。')
            .fontSize(13)
            .lineHeight(20)
            .fontColor('#6D7F79')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(17)
        .backgroundColor('#FFFFFF')
        .borderRadius(18)

        Column({ space: 10 }) {
          Text('自定义归类')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#173B34')
          Text('进入「内容库」，在搜索框下方输入名称并点击「新增归类」。新归类会持久化保存，并出现在筛选、统计和内容详情中。')
            .fontSize(14)
            .lineHeight(22)
            .fontColor('#4B615B')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(17)
        .backgroundColor('#FFFFFF')
        .borderRadius(18)

        Column({ space: 12 }) {
          Text('数据与隐私')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#173B34')
          Text('本版本只保存你主动分享的链接、标题和本地整理数据，不读取平台账号或平台私有收藏。数据仅保存在本机。')
            .fontSize(14)
            .lineHeight(22)
            .fontColor('#4B615B')
          Text('查看完整隐私政策')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor('#0B8268')
            .onClick(async () => {
              const context = getContext(this) as common.UIAbilityContext;
              try {
                await context.openLink('https://github.com/yyj7315/collection-genie/blob/main/PRIVACY.md');
              } catch (error) {
                promptAction.showToast({ message: `无法打开隐私政策：${String(error)}` });
              }
            })
          Text('问题反馈')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor('#0B8268')
            .onClick(async () => {
              const context = getContext(this) as common.UIAbilityContext;
              try {
                await context.openLink('https://github.com/yyj7315/collection-genie/issues');
              } catch (error) {
                promptAction.showToast({ message: `无法打开问题反馈：${String(error)}` });
              }
            })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(17)
        .backgroundColor('#FFFFFF')
        .borderRadius(18)

        Column({ space: 10 }) {
          Text('原始分享诊断')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#173B34')
          Text(this.shareTestResult.length > 0 ? this.shareTestResult : '尚无系统分享数据。')
            .fontSize(12)
            .lineHeight(18)
            .fontColor('#5F706B')
            .width('100%')
            .padding(12)
            .backgroundColor('#F2F6F4')
            .borderRadius(10)
            .copyOption(CopyOptions.LocalDevice)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(17)
        .backgroundColor('#FFFFFF')
        .borderRadius(18)
        .margin({ bottom: 18 })
      }
      .padding({ left: 16, right: 16 })
      .width('100%')
    }
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }

  @Builder
  private BottomNavigation() {
    Row() {
      ForEach(['首页', '内容库', '统计', '我的'], (label: string, index: number) => {
        Column({ space: 5 }) {
          Image(
            index === 0 ? $r('app.media.nav_home') :
            index === 1 ? $r('app.media.nav_library') :
            index === 2 ? $r('app.media.nav_stats') :
            $r('app.media.nav_profile')
          )
            .width(24)
            .height(24)
            .objectFit(ImageFit.Contain)
            .fillColor(this.activeTab === index ? '#0C8169' : '#80918C')
          Text(label)
            .fontSize(11)
            .lineHeight(16)
            .fontColor(this.activeTab === index ? '#0C8169' : '#8B9B96')
        }
        .height(50)
        .justifyContent(FlexAlign.Center)
        .layoutWeight(1)
        .onClick(() => {
          this.activeTab = index;
        })
      }, (label: string) => label)
    }
    .width('100%')
    .height(64 + this.bottomSafeInset)
    .padding({ top: 6, bottom: this.bottomSafeInset })
    .backgroundColor('#FBFDFC')
    .border({ width: { top: 1 }, color: '#E4ECE9' })
  }

  @Builder
  private DetailOverlay(item: CollectionItem) {
    Column() {
      Row({ space: 12 }) {
        Button('‹')
          .width(38)
          .height(38)
          .fontSize(26)
          .fontColor('#24443B')
          .backgroundColor('#EAF1EF')
          .onClick(() => {
            this.closeDetail();
          })
        Column({ space: 2 }) {
          Text('内容详情')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor('#173B34')
          Text(item.source)
            .fontSize(12)
            .fontColor('#758681')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        Blank()
        Text(item.status)
          .fontSize(12)
          .fontColor('#0B8268')
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .backgroundColor('#DFF3EC')
          .borderRadius(12)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 10 })

      Scroll() {
        Column({ space: 16 }) {
          Text(item.title)
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .lineHeight(34)
            .fontColor('#173B34')
            .width('100%')
          if (item.author.length > 0) {
            Text(`作者：${item.author}`)
              .fontSize(14)
              .fontColor('#61746F')
              .width('100%')
          }

          Row({ space: 10 }) {
            Button('打开原视频')
              .layoutWeight(1)
              .height(44)
              .backgroundColor('#168F77')
              .fontColor('#FFFFFF')
              .onClick(() => {
                this.openOriginal(item);
              })
            Button('复制链接')
              .layoutWeight(1)
              .height(44)
              .backgroundColor('#E5F1ED')
              .fontColor('#126B59')
              .onClick(() => {
                this.copyLink(item);
              })
          }
          .width('100%')

          Column({ space: 10 }) {
            Text('归类')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor('#2C4841')
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.editableCategories, (category: string) => {
                Text(category)
                  .fontSize(13)
                  .fontColor(item.category === category ? '#FFFFFF' : '#52655F')
                  .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                  .margin({ right: 8, bottom: 8 })
                  .backgroundColor(item.category === category ? this.categoryColor(category) : '#F0F5F3')
                  .borderRadius(14)
                  .onClick(() => {
                    this.setCategory(item, category);
                  })
              }, (category: string) => category)
            }
            .width('100%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(15)
          .backgroundColor('#FFFFFF')
          .borderRadius(16)

          Column({ space: 10 }) {
            Text('状态')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor('#2C4841')
            Row({ space: 8 }) {
              ForEach(['未看', '在看', '已完成'], (status: string) => {
                Text(status)
                  .fontSize(13)
                  .fontColor(item.status === status ? '#FFFFFF' : '#52655F')
                  .padding({ left: 14, right: 14, top: 8, bottom: 8 })
                  .backgroundColor(item.status === status ? '#178F78' : '#F0F5F3')
                  .borderRadius(14)
                  .onClick(() => {
                    this.setStatus(item, status);
                  })
              }, (status: string) => status)
            }
            .width('100%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(15)
          .backgroundColor('#FFFFFF')
          .borderRadius(16)

          Column({ space: 10 }) {
            Text('我的笔记')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor('#2C4841')
            TextArea({ text: item.notes, placeholder: '记下为什么收藏，下次就不用重新判断。' })
              .height(110)
              .fontSize(14)
              .backgroundColor('#F4F7F6')
              .borderRadius(12)
              .onChange((value: string) => {
                item.notes = value;
              })
            Button('保存笔记')
              .height(40)
              .backgroundColor('#E5F1ED')
              .fontColor('#126B59')
              .onClick(() => {
                this.saveNotes(item);
              })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(15)
          .backgroundColor('#FFFFFF')
          .borderRadius(16)

          Column({ space: 9 }) {
            Row() {
              Text('标签')
                .fontSize(14)
                .fontColor('#71827D')
              Blank()
              Text(item.tags.replaceAll('|', ' · '))
                .fontSize(14)
                .fontColor('#344C46')
            }
            .width('100%')
            Row() {
              Text('收藏时间')
                .fontSize(14)
                .fontColor('#71827D')
              Blank()
              Text(this.formatDate(item.collect_time))
                .fontSize(14)
                .fontColor('#344C46')
            }
            .width('100%')
            Row() {
              Text('打开次数')
                .fontSize(14)
                .fontColor('#71827D')
              Blank()
              Text(`${item.open_count} 次`)
                .fontSize(14)
                .fontColor('#344C46')
            }
            .width('100%')
          }
          .width('100%')
          .padding(15)
          .backgroundColor('#FFFFFF')
          .borderRadius(16)

          Button(this.detailDeleteArmed ? '再次点击确认删除' : '删除本应用记录')
            .height(44)
            .width('100%')
            .backgroundColor(this.detailDeleteArmed ? '#B4473B' : '#FBE8E5')
            .fontColor(this.detailDeleteArmed ? '#FFFFFF' : '#9C4035')
            .onClick(() => {
              this.deleteCurrent();
            })
            .margin({ bottom: 24 })
        }
        .padding({ left: 16, right: 16, top: 8 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F4F8F7')
    .zIndex(10)
  }

  build() {
    Stack() {
      Column() {
        if (this.activeTab === 0) {
          this.HomePage()
        } else if (this.activeTab === 1) {
          this.LibraryPage()
        } else if (this.activeTab === 2) {
          this.StatsPage()
        } else {
          this.SettingsPage()
        }
        this.BottomNavigation()
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#F4F8F7')

      if (this.selectedItem !== null) {
        this.DetailOverlay(this.selectedItem)
      }
    }
    .width('100%')
    .height('100%')
  }
}
