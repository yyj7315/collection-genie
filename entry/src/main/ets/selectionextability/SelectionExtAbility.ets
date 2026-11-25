import { Want } from '@kit.AbilityKit';
import {
  emitter,
  PanelInfo,
  PanelType,
  SelectionExtensionAbility,
  selectionManager
} from '@kit.BasicServicesKit';
import { rpc } from '@kit.IPCKit';
import {
  SELECTION_COLLECT_EVENT,
  SELECTION_PAYLOAD_KEY
} from './SelectionModel';

export default class SelectionExtAbility extends SelectionExtensionAbility {
  private panel: selectionManager.Panel | null = null;
  private connected: boolean = false;
  private selectionCallback = (info: selectionManager.SelectionInfo): void => {
    this.handleSelection(info).catch((error: Error) => {
      console.error(`Selection collection failed: ${String(error)}`);
    });
  };
  private collectCallback = (event: emitter.EventData): void => {
    this.collectSelectedText().catch((error: Error) => {
      console.error(`Starting collection genie failed: ${String(error)}`);
    });
  };

  onConnect(want: Want): rpc.RemoteObject {
    if (!this.connected) {
      try {
        selectionManager.on('selectionCompleted', this.selectionCallback);
        emitter.on(SELECTION_COLLECT_EVENT, this.collectCallback);
        this.connected = true;
      } catch (error) {
        console.error(`Selection service is unavailable: ${String(error)}`);
      }
    }
    return new rpc.RemoteObject('collection_genie_selection');
  }

  onDisconnect(): void {
    if (!this.connected) {
      return;
    }
    try {
      selectionManager.off('selectionCompleted', this.selectionCallback);
      emitter.off(SELECTION_COLLECT_EVENT, this.collectCallback);
    } catch (error) {
      console.error(`Selection cleanup failed: ${String(error)}`);
    }
    this.connected = false;
    if (this.panel !== null) {
      selectionManager.destroyPanel(this.panel).catch((error: Error) => {
        console.error(`Destroy selection panel failed: ${String(error)}`);
      });
      this.panel = null;
    }
  }

  private async handleSelection(info: selectionManager.SelectionInfo): Promise<void> {
    const selectedText = (await selectionManager.getSelectionContent()).trim();
    if (selectedText.length === 0) {
      return;
    }
    AppStorage.setOrCreate(SELECTION_PAYLOAD_KEY, selectedText);

    if (this.panel === null) {
      const panelInfo: PanelInfo = {
        panelType: PanelType.MENU_PANEL,
        x: Math.max(0, info.endDisplayX + 12),
        y: Math.max(0, info.endDisplayY + 16),
        width: 420,
        height: 80
      };
      this.panel = await selectionManager.createPanel(this.context, panelInfo);
      await this.panel.setUiContent('pages/SelectionMenuPanel');
    }
    await this.panel.moveToGlobalDisplay(
      Math.max(0, info.endDisplayX + 12),
      Math.max(0, info.endDisplayY + 16)
    );
    await this.panel.show();
  }

  private async collectSelectedText(): Promise<void> {
    const payload = (AppStorage.get<string>(SELECTION_PAYLOAD_KEY) ?? '').trim();
    if (payload.length === 0) {
      return;
    }
    const want: Want = {
      bundleName: 'com.yongjie.collectiongenie',
      abilityName: 'EntryAbility',
      parameters: {
        'collectionPayload': payload
      }
    };
    await this.context.startAbility(want);
    if (this.panel !== null) {
      await selectionManager.destroyPanel(this.panel);
      this.panel = null;
    }
  }
}
