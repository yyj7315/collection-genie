import { emitter } from '@kit.BasicServicesKit';
import { SELECTION_COLLECT_EVENT } from '../selectionextability/SelectionModel';

@Entry
@Component
struct SelectionMenuPanel {
  @StorageProp('selectionPayloadText') selectedText: string = '';

  private previewText(): string {
    const oneLine = this.selectedText.replace(/\s+/g, ' ').trim();
    return oneLine.length > 34 ? `${oneLine.substring(0, 34)}…` : oneLine;
  }

  build() {
    Row({ space: 12 }) {
      Column({ space: 3 }) {
        Text('收藏夹精灵')
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor('#173B34')
        Text(this.previewText().length > 0 ? this.previewText() : '收藏选中的内容')
          .fontSize(11)
          .fontColor('#6B7C77')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Button('收藏')
        .height(38)
        .fontSize(13)
        .backgroundColor('#168F77')
        .fontColor('#FFFFFF')
        .onClick(() => {
          emitter.emit(SELECTION_COLLECT_EVENT);
        })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 14, right: 12, top: 8, bottom: 8 })
    .backgroundColor('#FBFDFC')
    .border({ width: 1, color: '#DDE8E4' })
    .borderRadius(16)
  }
}
