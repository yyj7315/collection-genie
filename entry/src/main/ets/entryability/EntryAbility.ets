import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { systemShare } from '@kit.ShareKit';

interface SharedRecordView {
  utd: string;
  title: string;
  label: string;
  description: string;
  content: string;
  uri: string;
}

interface ShareTestResult {
  receivedAt: string;
  launchSource: string;
  wantUri: string;
  recordCount: number;
  records: SharedRecordView[];
  error: string;
}

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.parseIncoming(want);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.parseIncoming(want);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (error: BusinessError) => {
      if (error.code) {
        console.error(`Failed to load Index. Code: ${error.code}, message: ${error.message}`);
      }
    });
  }

  private parseIncoming(want: Want): void {
    const parameters = want.parameters;
    if (parameters !== undefined) {
      const directPayload = parameters['collectionPayload'];
      if (typeof directPayload === 'string' && directPayload.trim().length > 0) {
        this.publishDirectPayload(directPayload.trim(), want.bundleName ?? '同应用入口');
        return;
      }
    }
    this.parseShare(want);
  }

  private parseShare(want: Want): void {
    systemShare.getSharedData(want)
      .then((data: systemShare.SharedData) => {
        const records: SharedRecordView[] = [];
        data.getRecords().forEach((record: systemShare.SharedRecord) => {
          records.push({
            utd: record.utd ?? '',
            title: record.title ?? '',
            label: record.label ?? '',
            description: record.description ?? '',
            content: record.content ?? '',
            uri: record.uri ?? ''
          });
        });

        const result: ShareTestResult = {
          receivedAt: new Date().toISOString(),
          launchSource: want.bundleName ?? '',
          wantUri: want.uri ?? '',
          recordCount: records.length,
          records: records,
          error: ''
        };
        this.publishResult(result);
      })
      .catch((error: BusinessError) => {
        // 普通点击桌面图标启动时也会进入这里，不应覆盖已经收到的分享结果。
        if (AppStorage.get<string>('shareTestResult') === undefined) {
          const result: ShareTestResult = {
            receivedAt: '',
            launchSource: want.bundleName ?? '',
            wantUri: want.uri ?? '',
            recordCount: 0,
            records: [],
            error: `尚未收到分享。getSharedData: ${error.code} ${error.message}`
          };
          this.publishResult(result);
        }
      });
  }

  private publishDirectPayload(payload: string, launchSource: string): void {
    const result: ShareTestResult = {
      receivedAt: new Date().toISOString(),
      launchSource: launchSource,
      wantUri: '',
      recordCount: 1,
      records: [
        {
          utd: 'general.hyperlink',
          title: '',
          label: '划词扩展',
          description: '',
          content: payload,
          uri: ''
        }
      ],
      error: ''
    };
    AppStorage.setOrCreate('shareTestResult', JSON.stringify(result, null, 2));
    AppStorage.setOrCreate('sharePayloadText', payload);
    AppStorage.setOrCreate('shareReceived', true);
    AppStorage.setOrCreate('pendingSharePayloadText', payload);
    AppStorage.setOrCreate('shareSignal', Date.now());
  }

  private publishResult(result: ShareTestResult): void {
    AppStorage.setOrCreate('shareTestResult', JSON.stringify(result, null, 2));

    const firstRecord = result.records.length > 0 ? result.records[0] : undefined;
    const payloadText = firstRecord === undefined
      ? ''
      : [firstRecord.title, firstRecord.description, firstRecord.content, firstRecord.uri]
        .filter((value: string) => value.length > 0)
        .join('\n');
    AppStorage.setOrCreate('sharePayloadText', payloadText);
    AppStorage.setOrCreate('shareReceived', result.recordCount > 0);
    if (payloadText.length > 0) {
      AppStorage.setOrCreate('pendingSharePayloadText', payloadText);
      AppStorage.setOrCreate('shareSignal', Date.now());
    }
  }
}
