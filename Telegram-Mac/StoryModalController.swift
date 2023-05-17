//
//  StoryModalController.swift
//  Telegram
//
//  Created by Mike Renoir on 24.04.2023.
//  Copyright © 2023 Telegram. All rights reserved.
//

import Foundation
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import ColorPalette
import TGModernGrowingTextView

private struct Reaction {
    let item: UpdateMessageReaction
    let fromRect: CGRect?
}

struct StoryInitialIndex {
    let peerId: PeerId
    let id: Int32?
    let takeControl:((PeerId)->NSView?)?
}

struct StoryListEntry : Equatable, Comparable, Identifiable {
    let item: StoryListContext.PeerItemSet
    let index: Int
    
    static func <(lhs: StoryListEntry, rhs: StoryListEntry) -> Bool {
        return lhs.index < rhs.index
    }
    var stableId: AnyHashable {
        return item.peerId
    }
    var id: PeerId {
        return item.peerId
    }
    var count: Int {
        return item.items.count
    }
    var hasUnseen: Bool {
        return self.item.items.contains(where: { !isSeen($0) })
    }
    
    func isSeen(_ item: StoryListContext.Item) -> Bool {
        if self.item.maxReadId >= item.id {
            return true
        } else {
            return false
        }
    }
}



let storyTheme = generateTheme(palette: nightAccentPalette, cloudTheme: nil, bubbled: false, fontSize: 13, wallpaper: .init())


final class StoryInteraction : InterfaceObserver {
    struct State : Equatable {
        
        
        var inputs: [PeerId : ChatTextInputState] = [:]
        var entryState:[PeerId : Int32] = [:]
        var input: ChatTextInputState {
            if let entryId = entryId {
                if let input = inputs[entryId] {
                    return input
                }
            }
            return ChatTextInputState()
        }
        
        var mouseDown: Bool = false
        var inputInFocus: Bool = false
        var hasPopover: Bool = false
        var hasMenu: Bool = false
        var hasModal: Bool = false
        var windowIsKey: Bool = false
        var inTransition: Bool = false
        var isRecording: Bool = false
        var hasReactions: Bool = false
        var isSpacePaused: Bool = false
        var playingReaction: Bool = false
        var readingText: Bool = false
        var isMuted: Bool = false
        var storyId: Int32? = nil
        var entryId: PeerId? = nil
        var inputRecording: ChatRecordingState?
        var recordType: RecordingStateSettings = FastSettings.recordingState
        
        var isPaused: Bool {
            return mouseDown || inputInFocus || hasPopover || hasModal || !windowIsKey || inTransition || isRecording || hasMenu || hasReactions || playingReaction || isSpacePaused || readingText || inputRecording != nil
        }
        
    }
    fileprivate(set) var presentation: State
    init(presentation: State = .init()) {
        self.presentation = presentation
    }
    
    func startRecording(context: AccountContext, autohold: Bool) {
        let state: ChatRecordingState
        if self.presentation.recordType == .voice {
            state = ChatRecordingAudioState(context: context, liveUpload: false, autohold: autohold)
        } else {
            let videoState = ChatRecordingVideoState(context: context, liveUpload: false, autohold: autohold)
            state = videoState
            showModal(with: VideoRecorderModalController(state: state, pipeline: videoState.pipeline, sendMedia: { medias in
                
            }, resetState: { [weak self] in
                self?.resetRecording()
            }), for: context.window)
        }
        state.start()

        self.update { current in
            var current = current
            current.inputRecording = state
            return current
        }
    }
    
    func update(animated:Bool = true, _ f:(State)->State)->Void {
        let oldValue = self.presentation
        self.presentation = f(presentation)
        if oldValue != presentation {
            notifyObservers(value: presentation, oldValue:oldValue, animated: animated)
        }
    }
    
    func toggleMuted() {
        self.update { current in
            var current = current
            current.isMuted = !current.isMuted
            return current
        }
    }
    func flushPauses() {
        self.update { current in
            var current = current
            current.isSpacePaused = false
            return current
        }
    }
    
    func canBeMuted(_ story: StoryListContext.Item) -> Bool {
        return story.media._asMedia() is TelegramMediaFile
    }
    
    func updateInput(with text:String) {
        let state = ChatTextInputState(inputText: text, selectionRange: text.length ..< text.length, attributes: [])
        self.update({ current in
            var current = current
            if let entryId = current.entryId {
                current.inputs[entryId] = state
            }
            return current
        })
    }
    func appendText(_ text: NSAttributedString, selectedRange:Range<Int>? = nil) -> Range<Int> {

        var selectedRange = selectedRange ?? presentation.input.selectionRange
        let inputText = presentation.input.attributedString(storyTheme).mutableCopy() as! NSMutableAttributedString
        
        
        if selectedRange.upperBound - selectedRange.lowerBound > 0 {

            inputText.replaceCharacters(in: NSMakeRange(selectedRange.lowerBound, selectedRange.upperBound - selectedRange.lowerBound), with: text)
            selectedRange = selectedRange.lowerBound ..< selectedRange.lowerBound
        } else {
            inputText.insert(text, at: selectedRange.lowerBound)
        }
        
        let nRange:Range<Int> = selectedRange.lowerBound + text.length ..< selectedRange.lowerBound + text.length
        let state = ChatTextInputState(inputText: inputText.string, selectionRange: nRange, attributes: chatTextAttributes(from: inputText))
        self.update({ current in
            var current = current
            if let entryId = current.entryId {
                current.inputs[entryId] = state
            }
            return current
        })
        
        return selectedRange.lowerBound ..< selectedRange.lowerBound + text.length
    }
    
    func resetRecording() {
        update { current in
            var current = current
            current.inputRecording = nil
            return current
        }
    }
    
    deinit {
        var bp = 0
        bp += 1
    }
//
//    func appendText(_ text:String, selectedRange:Range<Int>? = nil) -> Range<Int> {
//        return self.appendText(NSAttributedString(string: text, font: .normal(theme.fontSize)), selectedRange: selectedRange)
//    }

}

final class StoryArguments {
    let context: AccountContext
    let interaction: StoryInteraction
    let chatInteraction: ChatInteraction
    let showEmojiPanel:(Control)->Void
    let showReactionsPanel:(Control)->Void
    let attachPhotoOrVideo:(ChatInteraction.AttachMediaType?)->Void
    let attachFile:()->Void
    let nextStory:()->Void
    let prevStory:()->Void
    let close:()->Void
    let openPeerInfo:(PeerId)->Void
    let openChat:(PeerId, MessageId?, ChatInitialAction?)->Void
    let sendMessage:()->Void
    let toggleRecordType:()->Void
    let deleteStory:(Int32)->Void
    init(context: AccountContext, interaction: StoryInteraction, chatInteraction: ChatInteraction, showEmojiPanel:@escaping(Control)->Void, showReactionsPanel:@escaping(Control)->Void, attachPhotoOrVideo:@escaping(ChatInteraction.AttachMediaType?)->Void, attachFile:@escaping()->Void, nextStory:@escaping()->Void, prevStory:@escaping()->Void, close:@escaping()->Void, openPeerInfo:@escaping(PeerId)->Void, openChat:@escaping(PeerId, MessageId?, ChatInitialAction?)->Void, sendMessage:@escaping()->Void, toggleRecordType:@escaping()->Void, deleteStory:@escaping(Int32)->Void) {
        self.context = context
        self.interaction = interaction
        self.chatInteraction = chatInteraction
        self.showEmojiPanel = showEmojiPanel
        self.showReactionsPanel = showReactionsPanel
        self.attachPhotoOrVideo = attachPhotoOrVideo
        self.attachFile = attachFile
        self.nextStory = nextStory
        self.prevStory = prevStory
        self.close = close
        self.openPeerInfo = openPeerInfo
        self.openChat = openChat
        self.sendMessage = sendMessage
        self.toggleRecordType = toggleRecordType
        self.deleteStory = deleteStory
    }
    
    func longDown() {
        self.interaction.update { current in
            var current = current
            current.mouseDown = true
            return current
        }
    }
    func longUp() {
        self.interaction.update { current in
            var current = current
            current.mouseDown = false
            return current
        }
    }
    func inputFocus() {
        self.interaction.update { current in
            var current = current
            current.inputInFocus = true
            current.isSpacePaused = true
            return current
        }
    }
    func inputUnfocus() {
        self.interaction.update { current in
            var current = current
            current.inputInFocus = false
            current.isSpacePaused = false
            return current
        }
    }
    
    func startRecording(autohold: Bool) {
        self.interaction.startRecording(context: context, autohold: autohold)
    }
    
    deinit {
        var bp = 0
        bp += 1
    }
}

private let next_chevron = NSImage(named: "Icon_StoryChevron")!.precomposed(NSColor.white.withAlphaComponent(0.53))
private let prev_chevron = NSImage(named: "Icon_StoryChevron")!.precomposed(NSColor.white.withAlphaComponent(0.53), flipHorizontal: true)

private let next_chevron_hover = NSImage(named: "Icon_StoryChevron")!.precomposed(NSColor.white.withAlphaComponent(1))
private let prev_chevron_hover = NSImage(named: "Icon_StoryChevron")!.precomposed(NSColor.white.withAlphaComponent(1), flipHorizontal: true)

private let close_image = NSImage(named: "Icon_StoryClose")!.precomposed(NSColor.white.withAlphaComponent(0.53))
private let close_image_hover = NSImage(named: "Icon_StoryClose")!.precomposed(NSColor.white.withAlphaComponent(1))


private func storyReactions(context: AccountContext, peerId: PeerId, react: @escaping(Reaction)->Void, onClose: @escaping()->Void) -> Signal<NSView?, NoError> {
    
    
    let builtin = context.reactions.stateValue
    let peerAllowed: Signal<PeerAllowedReactions?, NoError> = getCachedDataView(peerId: peerId, postbox: context.account.postbox)
    |> map { cachedData in
        if let cachedData = cachedData as? CachedGroupData {
            return cachedData.allowedReactions.knownValue
        } else if let cachedData = cachedData as? CachedChannelData {
            return cachedData.allowedReactions.knownValue
        } else {
            return nil
        }
    }
    |> take(1)
    
    var orderedItemListCollectionIds: [Int32] = []
    
    orderedItemListCollectionIds.append(Namespaces.OrderedItemList.CloudRecentReactions)
    orderedItemListCollectionIds.append(Namespaces.OrderedItemList.CloudTopReactions)

    let reactions:Signal<[RecentReactionItem], NoError> = context.diceCache.emojies_reactions |> map { view in
        
        var recentReactionsView: OrderedItemListView?
        var topReactionsView: OrderedItemListView?
        for orderedView in view.orderedItemListsViews {
            if orderedView.collectionId == Namespaces.OrderedItemList.CloudRecentReactions {
                recentReactionsView = orderedView
            } else if orderedView.collectionId == Namespaces.OrderedItemList.CloudTopReactions {
                topReactionsView = orderedView
            }
        }
        var recentReactionsItems:[RecentReactionItem] = []
        var topReactionsItems:[RecentReactionItem] = []

        if let recentReactionsView = recentReactionsView {
            for item in recentReactionsView.items {
                guard let item = item.contents.get(RecentReactionItem.self) else {
                    continue
                }
                recentReactionsItems.append(item)
            }
        }
        if let topReactionsView = topReactionsView {
            for item in topReactionsView.items {
                guard let item = item.contents.get(RecentReactionItem.self) else {
                    continue
                }
                topReactionsItems.append(item)
            }
        }
        return topReactionsItems.filter { value in
            if context.isPremium {
                return true
            } else {
                if case .custom = value.content {
                    return false
                } else {
                    return true
                }
            }
        }
    }
    
    
    let signal = combineLatest(queue: .mainQueue(), builtin, peerAllowed, reactions)
    |> take(1)

    return signal |> map { builtin, peerAllowed, reactions in
        let enabled = builtin?.enabled ?? []

        var available:[ContextReaction] = []
        
        
        let accessToAll: Bool = true
        
        available = reactions.compactMap { value in
            switch value.content {
            case let .builtin(emoji):
                if let generic = enabled.first(where: { $0.value.string == emoji }) {
                    return .builtin(value: generic.value, staticFile: generic.staticIcon, selectFile: generic.selectAnimation, appearFile: generic.appearAnimation, isSelected: false)
                } else {
                    return nil
                }
            case let .custom(file):
                return .custom(value: .custom(file.fileId.id), fileId: file.fileId.id, file, isSelected: false)
            }
        }
        
        
        guard !available.isEmpty else {
            return nil
        }
        
        if accessToAll {
            available = Array(available.prefix(6))
        }
        
        let width = ContextAddReactionsListView.width(for: available.count, maxCount: 6, allowToAll: accessToAll)
        
        
        let rect = NSMakeRect(0, 0, width + 20 + (accessToAll ? 0 : 20), 40 + 20)
        
        
        let panel = Window(contentRect: rect, styleMask: [.fullSizeContentView], backing: .buffered, defer: false)
        panel._canBecomeMain = false
        panel._canBecomeKey = false
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        

        let reveal:((NSView & StickerFramesCollector)->Void)?
        
       
        
        reveal = { view in
            let window = ReactionsWindowController(context, peerId: peerId, selectedItems: [], react: { sticker, fromRect in
                let value: UpdateMessageReaction
                if let bundle = sticker.file.stickerText {
                    value = .builtin(bundle)
                } else {
                    value = .custom(fileId: sticker.file.fileId.id, file: sticker.file)
                }
                react(.init(item: value, fromRect: fromRect))
                onClose()
            }, onClose: onClose, presentation: storyTheme)
            window.show(view)
        }
        
        let view = ContextAddReactionsListView(frame: rect, context: context, list: available, add: { value, checkPrem, fromRect in
            react(.init(item: value.toUpdate(), fromRect: fromRect))
            onClose()
        }, radiusLayer: nil, revealReactions: reveal, presentation: storyTheme)
        
        return view
    } |> deliverOnMainQueue
}

private final class StoryViewController: Control, Notifable {
    
    class NavigationButton : Control {
        private let button = ImageButton()
        private var photo: AvatarControl?
        private var peer: Peer?
        private var isNext: Bool = false
        private var context: AccountContext?
        required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            addSubview(self.button)
            self.scaleOnClick = true
            self.button.userInteractionEnabled = false
            
           
        }
        
        override func mouseMoved(with event: NSEvent) {
            super.mouseMoved(with: event)
            self.updateVisibility()
        }
        override func mouseEntered(with event: NSEvent) {
            super.mouseEntered(with: event)
            self.updateVisibility()
        }
        override func mouseExited(with event: NSEvent) {
            super.mouseExited(with: event)
            self.updateVisibility()
        }
        
        func updateVisibility(animated: Bool = true) {
            if let photo = self.photo  {
                photo._change(opacity: photo._mouseInside() || button.mouseInside() ? 1.0 : 0.8, animated: animated)
            }
            if button.mouseInside() || self.photo?._mouseInside() == true {
                button.change(opacity: 1.0, animated: animated)
            } else {
                button.change(opacity: 0.8, animated: animated)
            }
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        
        func update(with peer: Peer?, context: AccountContext, isNext: Bool, animated: Bool) {
            self.isNext = isNext
            if peer?.id != self.peer?.id {
                self.peer = peer
                self.context = context
                if let photo = self.photo {
                    performSubviewRemoval(photo, animated: animated)
                    self.photo = nil
                }
                if let peer = peer {
                    let photo = AvatarControl(font: .avatar(18))
                    photo.setFrameSize(NSMakeSize(30, 30))
                    addSubview(photo)
                    self.photo = photo
                    photo.center()
                    photo.userInteractionEnabled = false
                    photo.layer?.opacity = 0.8
                    
                    photo.setPeer(account: context.account, peer: peer)
                    
                    if animated {
                        photo.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                        //photo.layer?.animateScaleSpring(from: 0.1, to: 1, duration: 0.2)
                    }
                }
                if isNext {
                    button.set(image: next_chevron_hover, for: .Normal)
//                    button.set(image: next_chevron_hover, for: .Hover)
//                    button.set(image: next_chevron_hover, for: .Highlight)
                } else {
                    button.set(image: prev_chevron_hover, for: .Normal)
//                    button.set(image: prev_chevron_hover, for: .Hover)
//                    button.set(image: prev_chevron_hover, for: .Highlight)
                }
                
                button.sizeToFit(.zero, NSMakeSize(30, 30), thatFit: true)
                button.sizeToFit(.zero, NSMakeSize(30, 30), thatFit: true)
                
               

                button.controlOpacityEventIgnored = true
                button.controlOpacityEventIgnored = true

            }
            self.updateVisibility(animated: false)
            needsLayout = true
        }
        
        
        override func layout() {
            self.photo?.center()
            if let photo = self.photo {
                photo.isHidden = frame.width < 100
                if !photo.isHidden {
                    if isNext {
                        button.centerY(x: photo.frame.minX - button.frame.width)
                    } else {
                        button.centerY(x: photo.frame.maxX)
                    }
                } else {
                    button.center()
                }
            } else {
                button.center()
            }
        }
    }
    
    class TooptipView : NSVisualEffectView {
        
        enum Source {
            case reaction(Reaction)
            case media([Media])
            case text
        }
        private let textView = TextView()
        private let button = TitleButton()
        private let media = View(frame: NSMakeRect(0, 0, 24, 24))
        
        required override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            self.wantsLayer = true
            self.state = .active
            self.material = .ultraDark
            self.blendingMode = .withinWindow
            textView.userInteractionEnabled = false
            textView.isSelectable = false
            addSubview(textView)
            addSubview(button)
            addSubview(media)
            button.autohighlight = false
            button.scaleOnClick = true
            self.layer?.cornerRadius = 10
        }
        
        func update(source: Source, size: NSSize, context: AccountContext, callback: @escaping()->Void) {
            let title: String
            var mediaFile: TelegramMediaFile
            switch source {
            case .media:
                title = "Media Sent."
                mediaFile = MenuAnimation.menu_success.file
            case let .reaction(reaction):
                title = "Reaction Sent."
                var file: TelegramMediaFile?
                switch reaction.item {
                case let .custom(_, f):
                    file = f
                case let .builtin(string):
                    let reaction = context.reactions.available?.reactions.first(where: { $0.value.string == string })
                    file = reaction?.selectAnimation
                }
                if let file = file {
                    mediaFile = file
                } else {
                    mediaFile = MenuAnimation.menu_success.file
                }
            case .text:
                title = "Message Sent."
                mediaFile = MenuAnimation.menu_success.file
            }
            
            let mediaLayer = InlineStickerItemLayer(account: context.account, file: mediaFile, size: NSMakeSize(24, 24), playPolicy: .toEnd(from: 0), getColors: { file in
                if file == MenuAnimation.menu_success.file {
                    return []
                } else {
                    return []
                }
            })
            mediaLayer.isPlayable = true
            
            self.media.layer?.addSublayer(mediaLayer)
            
            let layout = TextViewLayout(.initialize(string: title, color: storyTheme.colors.text, font: .normal(.text)))
            
            
            self.button.set(font: .medium(.text), for: .Normal)
            self.button.set(color: storyTheme.colors.accent, for: .Normal)
            self.button.set(text: "View in Chat", for: .Normal)
            self.button.sizeToFit(NSMakeSize(10, 10), .zero, thatFit: false)
            
            layout.measure(width: size.width - 16 - 16 - self.button.frame.width - media.frame.width - 10 - 10)
            textView.update(layout)

            
            self.button.set(handler: { _ in
                callback()
            }, for: .Click)
            
            self.setFrameSize(size)
            self.updateLayout(size: size, transition: .immediate)
        }
        
        func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
            transition.updateFrame(view: media, frame: media.centerFrameY(x: 16))
            transition.updateFrame(view: textView, frame: textView.centerFrameY(x: media.frame.maxX + 10))
            transition.updateFrame(view: button, frame: button.centerFrameY(x: size.width - button.frame.width - 16))
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
    
   
    private var current: StoryListView?
    private var arguments:StoryArguments?
    
    private let next_button: NavigationButton = NavigationButton(frame: .zero)
    private let prev_button: NavigationButton = NavigationButton(frame: .zero)
    private let close: ImageButton = ImageButton()

    private var entries:[StoryListEntry] = []
    
    
    private var currentIndex: Int? = nil
    
    private let container = View()
    
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(container)
        
        
        addSubview(prev_button)
        addSubview(next_button)
        
        next_button.controlOpacityEventIgnored = true
        prev_button.controlOpacityEventIgnored = true

        
        close.set(image: close_image, for: .Normal)
        close.set(image: close_image_hover, for: .Hover)
        close.set(image: close_image_hover, for: .Highlight)
        close.sizeToFit(.zero, NSMakeSize(50, 50), thatFit: true)
        close.autohighlight = false
        close.scaleOnClick = true
        
        close.set(handler: { [weak self] _ in
            self?.arguments?.close()
        }, for: .Click)
        
        
        addSubview(close)
       
                
        self.updateLayout(size: self.frame.size, transition: .immediate)
        
        prev_button.set(handler: { [weak self] _ in
            self?.processGroupResult(.moveBack, animated: true)
        }, for: .Click)
        
        next_button.set(handler: { [weak self] _ in
            self?.processGroupResult(.moveNext, animated: true)
        }, for: .Click)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        self.updatePrevNextControls(event)
    }
    
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        self.updatePrevNextControls(event)
    }
    
    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        self.updatePrevNextControls(event)
    }
    
    func notify(with value: Any, oldValue: Any, animated: Bool) {
        if let event = NSApp.currentEvent {
            if !self.inTransition {
                self.updatePrevNextControls(event, animated: animated)
            }
        }
    }
    
    func isEqual(to other: Notifable) -> Bool {
        return self === other as? StoryViewController
    }
    
    var isPaused: Bool {
        return self.arguments?.interaction.presentation.isPaused ?? false
    }
    var isInputFocused: Bool {
        return self.arguments?.interaction.presentation.inputInFocus ?? false
    }
    var isTextEmpty: Bool {
        return self.arguments?.interaction.presentation.input.inputText.isEmpty == true
    }
    
    var hasNextGroup: Bool {
        guard let currentIndex = self.currentIndex, !isPaused else {
            return false
        }
        return currentIndex < entries.count - 1
    }
    var hasPrevGroup: Bool {
        guard let currentIndex = self.currentIndex, !isPaused else {
            return false
        }
        return currentIndex > 0
    }
    
    private func updatePrevNextControls(_ event: NSEvent, animated: Bool = true) {
        guard let current = self.current, let index = self.currentIndex, let arguments = self.arguments else {
            return
        }
        
        let nextEntry = self.entries[min(index + 1, entries.count - 1)]
        let prevEntry = self.entries[max(index - 1, 0)]
        
        self.prev_button.update(with: prevEntry.item.peer?._asPeer(), context: arguments.context, isNext: false, animated: animated)
        self.next_button.update(with: nextEntry.item.peer?._asPeer(), context: arguments.context, isNext: true, animated: animated)

        let point = self.convert(event.locationInWindow, from: nil)
        
        if point.x < current.contentRect.minX {
            self.prev_button.change(opacity: hasPrevGroup ? 1 : 0, animated: animated)
            self.next_button.change(opacity: 0, animated: animated)
        } else {
            self.prev_button.change(opacity: 0, animated: animated)
        }
        
        if point.x > current.contentRect.maxX {
            self.next_button.change(opacity: hasNextGroup ? 1 : 0, animated: animated)
            self.prev_button.change(opacity: 0, animated: animated)
        } else {
            self.next_button.change(opacity: 0, animated: animated)
        }
    }
    
    
    
    
    func update(context: AccountContext, items: [StoryListContext.PeerItemSet], initial: StoryInitialIndex?) {
                
        
        if items.isEmpty {
            return
        }
        
        var initial = initial

        
        var entries:[StoryListEntry] = []
        var index: Int = 0
        for itemSet in items {
            entries.append(.init(item: itemSet, index: index))
            index += 1
        }
                
        
        let (deleteIndices, indicesAndItems, updateIndices) = mergeListsStableWithUpdates(leftList: self.entries, rightList: entries)
        
        
        let previous = self.entries
        
        for rdx in deleteIndices.reversed() {
            self.entries.remove(at: rdx)
        }
        
        
        for (idx, item, _) in indicesAndItems {
            self.entries.insert(item, at: idx)
        }
        for (idx, item, _) in updateIndices {
            let item =  item
            self.entries[idx] = item
        }
        
        if let current = self.current {
            let entry = self.entries.first(where: { $0.id == current.id })
            
            if let entry = entry  {
                current.update(context: context, entry: entry, selected: nil)
            } else  {
                let prevIndex = previous.firstIndex(where: { $0.id == current.id })
                if let prevIndex = prevIndex {
                    let index = min(prevIndex, entries.count - 1)
                    self.current?.removeFromSuperview()
                    self.current = nil
                    initial = .init(peerId: entries[index].id, id: nil, takeControl: initial?.takeControl)
                }
            }
        }
        
        if self.current == nil {
            let storyView = StoryListView(frame: bounds)
            storyView.setArguments(self.arguments)
            
            
            
            let initialEntryIndex = entries.firstIndex(where: { $0.id == initial?.peerId }) ?? 0
            let entry = self.entries[initialEntryIndex]
            let entryId = entry.item.peerId
            
            self.currentIndex = initialEntryIndex
                        
            let initialId = self.arguments?.interaction.presentation.entryState[entryId] ?? initial?.id
            let initialIndex = entry.item.items.firstIndex(where: { $0.id == initialId }) ?? entry.item.items.firstIndex(where: { !entry.isSeen($0) }) ?? 0
            
            storyView.update(context: context, entry: entry, selected: initialIndex)
            self.current = storyView
            
            
            container.addSubview(storyView)
          
            arguments?.interaction.update(animated: false, { current in
                var current = current
                current.entryId = entryId
                return current
            })
            
            if let control = initial?.takeControl?(entryId) {
                storyView.animateAppearing(from: control)
            }
        }
        
        if let event = NSApp.currentEvent {
            self.updatePrevNextControls(event)
        }
    }
    
    func delete() -> KeyHandlerResult {
        if let storyId = self.arguments?.interaction.presentation.storyId, arguments?.interaction.presentation.inputInFocus == false {
            if self.arguments?.interaction.presentation.entryId == self.arguments?.context.peerId {
                self.arguments?.deleteStory(storyId)
                return .invoked
            }
        }
        return .rejected
    }
    
    func previous() -> KeyHandlerResult {
        if isInputFocused {
            return .invokeNext
        }
        guard !inTransition, let result = self.current?.previous() else {
            return .invokeNext
        }
        self.processGroupResult(result, animated: true)

        return .invoked
    }
    func next() -> KeyHandlerResult {
        if isInputFocused {
            return .invokeNext
        }
        guard !inTransition, let result = self.current?.next() else {
            return .invokeNext
        }
        let previousIndex = self.processGroupResult(result, animated: true)
        if previousIndex == self.currentIndex, result == .moveNext {
            self.close.send(event: .Click)
        }
        return .invoked
    }
    
    private var inTransition: Bool {
        get {
            return self.arguments?.interaction.presentation.inTransition ?? false
        }
        set {
            self.arguments?.interaction.update { current in
                var current = current
                current.inTransition = newValue
                return current
            }
        }
    }
    
    @discardableResult private func processGroupResult(_ result: StoryListView.UpdateIndexResult, animated: Bool, bySwipe: Bool = false) -> Int? {
        
        let previousIndex = self.currentIndex

        
        guard let currentIndex = self.currentIndex, let context = self.arguments?.context, !inTransition else {
            return previousIndex
        }
        
        
        if self.isInputFocused {
            self.resetInputView()
            return previousIndex
        }
        
        let nextGroupIndex: Int?
        switch result {
        case .invoked:
            nextGroupIndex = nil
        case .moveNext:
            nextGroupIndex = currentIndex + 1
        case .moveBack:
            nextGroupIndex = currentIndex - 1
        }
        
        if let nextGroupIndex = nextGroupIndex {
            if nextGroupIndex >= 0 && nextGroupIndex < self.entries.count {
                
                inTransition = true
                
                self.arguments?.interaction.flushPauses()
                
                let entry = entries[nextGroupIndex]
                let entryId = entry.id
                
                
                let isNext = currentIndex < nextGroupIndex
                
                let initial = arguments?.interaction.presentation.entryState[entryId]
                
                let initialIndex = entry.item.items.firstIndex(where: { $0.id == initial }) ?? entry.item.items.firstIndex(where: { !entry.isSeen($0) }) ?? (!isNext ? entry.count - 1 : 0)
                self.currentIndex = nextGroupIndex
                
                self.arguments?.interaction.update { current in
                    var current = current
                    current.entryId = entryId
                    return current
                }
                
                let storyView = StoryListView(frame: bounds)
                storyView.setArguments(self.arguments)
                
                storyView.update(context: context, entry: entry, selected: initialIndex)
                
                
                let previous = self.current
                self.current = storyView
                if isNext {
                    container.addSubview(storyView, positioned: .above, relativeTo: previous)
                } else {
                    container.addSubview(storyView, positioned: .below, relativeTo: previous)
                }
                
                if let previous = previous {
                    storyView.initAnimateTranslate(previous: previous, direction: isNext ? .left : .right)
                    if !bySwipe {
                        storyView.translate(progress: 0, finish: true, completion: { [weak self] completion, _ in
                            self?.inTransition = false
                        })
                    }
                }
                
            } else {
                self.close.send(event: .Click)
                //current?.shake(beep: false)
            }
        }
        if let event = NSApp.currentEvent {
            self.updatePrevNextControls(event)
        }
        
        return previousIndex
    }

    
    func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        transition.updateFrame(view: container, frame: size.bounds)
        if let current = self.current {
            transition.updateFrame(view: current, frame: size.bounds)
            current.updateLayout(size: size, transition: transition)

            transition.updateFrame(view: prev_button, frame: NSMakeRect(0, 0, (size.width - current.contentRect.width) / 2, size.height))
            transition.updateFrame(view: next_button, frame: NSMakeRect((size.width - current.contentRect.width) / 2 + current.contentRect.width, 0, (size.width - current.contentRect.width) / 2, size.height))
            
        }
        if let overlay = self.reactionsOverlay {
            transition.updateFrame(view: overlay, frame: size.bounds)
        }
        transition.updateFrame(view: close, frame: NSMakeRect(size.width - close.frame.width, 0, 50, 50))
    }
    
    var inputView: NSTextView? {
        return self.current?.textView
    }
    var inputTextView: TGModernGrowingTextView? {
        return self.current?.inputTextView
    }
    func makeUrl() {
        self.current?.makeUrl()
    }
    
    func resetInputView() {
        self.current?.resetInputView()
    }
    func setArguments(_ arguments: StoryArguments?) -> Void {
        self.arguments = arguments
        self.current?.setArguments(arguments)
    }
    
    private var reactionsOverlay: Control? = nil
   
    func closeReactions() {
        if let view = self.reactionsOverlay {
            performSubviewRemoval(view, animated: true)
            self.reactionsOverlay = nil
        }
        
        self.arguments?.interaction.update { current in
            var current = current
            current.hasReactions = false
            return current
        }
    }
    
    func playReaction(_ reaction: Reaction) -> Void {
        
        guard let arguments = self.arguments else {
            return
        }
        
        let context = arguments.context
        
        var file: TelegramMediaFile?
        var effectFileId: Int64?
        var effectFile: TelegramMediaFile?
        switch reaction.item {
        case let .custom(_, f):
            file = f
            effectFileId = f?.fileId.id
        case let .builtin(string):
            let reaction = context.reactions.available?.reactions.first(where: { $0.value.string == string })
            file = reaction?.selectAnimation
            effectFile = reaction?.aroundAnimation
        }
        
        guard let icon = file else {
            return
        }
       
        
        arguments.interaction.update { current in
            var current = current
            current.playingReaction = true
            current.inTransition = true
            return current
        }
        let overlay = View(frame: NSMakeRect(0, 0, 300, 300))
        addSubview(overlay)
        overlay.center()
        
        let finish:()->Void = { [weak arguments, weak overlay] in
            arguments?.interaction.update { current in
                var current = current
                current.playingReaction = false
                current.inTransition = false
                return current
            }
            if let overlay = overlay {
                performSubviewRemoval(overlay, animated: true)
            }
        }
        
        let play:(NSView, TelegramMediaFile)->Void = { container, icon in
            
            let layer = InlineStickerItemLayer(account: context.account, inlinePacksContext: context.inlinePacksContext, emoji: .init(fileId: icon.fileId.id, file: icon, emoji: ""), size: NSMakeSize(30, 30), playPolicy: .once)
            layer.isPlayable = true
            
            layer.frame = NSMakeRect((container.frame.width - layer.frame.width) / 2, (container.frame.height - layer.frame.height) / 2, layer.frame.width, layer.frame.height)
            container.layer?.addSublayer(layer)

            
            if let effectFileId = effectFileId {
                let player = CustomReactionEffectView(frame: NSMakeSize(300, 300).bounds, context: context, fileId: effectFileId)
                player.isEventLess = true
                player.triggerOnFinish = { [weak player] in
                    player?.removeFromSuperview()
                    finish()
                }
                let rect = CGRect(origin: CGPoint(x: 0, y: 0), size: player.frame.size)
                player.frame = rect
                container.addSubview(player)
            } else if let effectFile = effectFile {
                let player = InlineStickerItemLayer(account: context.account, file: effectFile, size: NSMakeSize(150, 150), playPolicy: .playCount(1))
                player.isPlayable = true
                player.frame = NSMakeRect(75, 75, 150, 150)
                container.layer?.addSublayer(player)
                player.triggerOnState = (.finished, { [weak player] state in
                    player?.removeFromSuperlayer()
                    finish()
                })
            }
            
        }
        
        let layer = InlineStickerItemLayer(account: context.account, file: icon, size: NSMakeSize(30, 30))

            let completed: (Bool)->Void = { [weak overlay] _ in
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
            DispatchQueue.main.async {
                if let container = overlay {
                    play(container, icon)
                }
            }
        }
        if let fromRect = reaction.fromRect {
            let toRect = overlay.convert(overlay.frame.size.bounds, to: nil)
            
            let from = fromRect.origin.offsetBy(dx: fromRect.width / 2, dy: fromRect.height / 2)
            let to = toRect.origin.offsetBy(dx: toRect.width / 2, dy: toRect.height / 2)
            parabollicReactionAnimation(layer, fromPoint: from, toPoint: to, window: context.window, completion: completed)
        } else {
            completed(true)
        }
        
    }
    
    func showReactions(_ view: NSView, control: Control) {
        
        guard let superview = control.superview else {
            return
        }
        
        let reactionsOverlay = Control(frame: bounds)
        reactionsOverlay.backgroundColor = NSColor.black.withAlphaComponent(0.2)
        reactionsOverlay.addSubview(view)
        addSubview(reactionsOverlay)
        
        
        reactionsOverlay.set(handler: { [weak self] _ in
            self?.closeReactions()
        }, for: .Click)
        
        self.reactionsOverlay = reactionsOverlay
        
        reactionsOverlay.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
        
        
        let point = superview.convert(control.frame.origin, to: reactionsOverlay)
        
        view.setFrameOrigin(NSMakePoint(point.x - view.frame.width + 75, point.y - view.frame.height + 5))
        
        self.arguments?.interaction.update { current in
            var current = current
            current.hasReactions = true
            return current
        }
    }
    
    func animateDisappear(_ initialId: StoryInitialIndex?) {
        if let current = self.current, let id = current.id, let control = initialId?.takeControl?(id) {
            current.animateDisappearing(to: control)
        }
    }
    
    deinit {
        tooltipDisposable.dispose()
    }
    
    private var currentTooltip: TooptipView?
    private let tooltipDisposable = MetaDisposable()
    func showTooltip(_ source: TooptipView.Source) {
        
        self.resetInputView()
        
        if let view = currentTooltip {
            performSubviewRemoval(view, animated: true, scale: true)
            self.currentTooltip = nil
            self.tooltipDisposable.set(nil)
        }
        
        guard let arguments = self.arguments, let current = self.current, let entryId = arguments.interaction.presentation.entryId else {
            return
        }
        
        let tooltip = TooptipView(frame: .zero)
        
        tooltip.update(source: source, size: NSMakeSize(current.contentRect.width - 20, 40), context: arguments.context, callback: { [weak arguments] in
            arguments?.openChat(entryId, nil, nil)
        })
        
        self.addSubview(tooltip)
        tooltip.centerX(y: current.contentRect.maxY - 50 - 10 - tooltip.frame.height - 40)
        
        tooltip.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
        tooltip.layer?.animatePosition(from: tooltip.frame.origin.offsetBy(dx: 0, dy: 20), to: tooltip.frame.origin)
        let signal = Signal<Void, NoError>.single(Void()) |> delay(3.5, queue: .mainQueue())
        self.tooltipDisposable.set(signal.start(completed: { [weak self] in
            if let view = self?.currentTooltip {
                performSubviewRemoval(view, animated: true)
                self?.currentTooltip = nil
            }
        }))
        
        self.currentTooltip = tooltip
    }
    
    private var scrollDeltaX: CGFloat = 0
    private var scrollDeltaY: CGFloat = 0

    private var previousIndex: Int? = nil
    
    private func returnGroupIndex(_ index: Int, previous: StoryListView) {
        self.currentIndex = index
        let entryId = self.entries[index].id
        
        let cur = self.current
        self.current?.removeFromSuperview()
        
        self.current = previous
        
        let storyId = previous.storyId
        
        container.addSubview(previous, positioned: .above, relativeTo: cur)

        self.arguments?.interaction.update { current in
            var current = current
            current.entryId = entryId
            current.inTransition = false
            current.storyId = storyId
            return current
        }
    }
    
    override func scrollWheel(with theEvent: NSEvent) {
        
        
        let completeTransition:(Bool, StoryListView)->Void = { [weak self] completed, previous in
            if !completed, let previousIndex = self?.previousIndex {
                self?.returnGroupIndex(previousIndex, previous: previous)
            } else {
                self?.inTransition = false
            }
        }
        
        if theEvent.phase == .began {
            if self.inTransition {
                return
            }
            
            scrollDeltaX = theEvent.scrollingDeltaX
            if scrollDeltaX == 0 {
                scrollDeltaY = theEvent.scrollingDeltaY
            }
            
            if scrollDeltaX > 0 {
                previousIndex = self.processGroupResult(.moveBack, animated: true, bySwipe: true)
            } else if scrollDeltaX < 0 {
                previousIndex = self.processGroupResult(.moveNext, animated: true, bySwipe: true)
            }
        } else if theEvent.phase == .changed {
            let previous = self.scrollDeltaX
            if scrollDeltaX > 0, scrollDeltaX + theEvent.scrollingDeltaX <= 0 {
                scrollDeltaX = 1
            } else if scrollDeltaX < 0, scrollDeltaX + theEvent.scrollingDeltaX >= 0 {
                scrollDeltaX = -1
            } else {
                scrollDeltaX += theEvent.scrollingDeltaX
            }

            if scrollDeltaY != 0 {
                scrollDeltaY += theEvent.scrollingDeltaY
            }
            scrollDeltaX = min(max(scrollDeltaX, -300), 300)
            
            let autofinish = abs(abs(previous) - abs(scrollDeltaX)) > 60
            
            
            self.current?.translate(progress: min(abs(scrollDeltaX / 300), 1), finish: autofinish, completion: completeTransition)
        } else if theEvent.phase == .ended {
            let progress = min(abs(scrollDeltaX / 300), 1)
            self.current?.translate(progress: progress, finish: true, cancel: progress < 0.5, completion: completeTransition)
            if scrollDeltaY > 50 || scrollDeltaY < -50 {
                self.close.send(event: .Click)
            }
            scrollDeltaX = 0
            scrollDeltaY = 0
        } else if theEvent.phase == .cancelled {
            let progress = min(abs(scrollDeltaX / 300), 1)
            let cancel = progress < 0.5
            self.current?.translate(progress: cancel ? 0 : 1, finish: true, cancel: progress < 0.5, completion: completeTransition)
            scrollDeltaX = 0
            scrollDeltaY = 0
        }
    }
    
    override func layout() {
        super.layout()
        self.updateLayout(size: self.frame.size, transition: .immediate)
    }
}

final class StoryModalController : ModalViewController, Notifable {
    private let context: AccountContext
    private var initialId: StoryInitialIndex?
    private let stories: StoryListContext
    private let entertainment: EntertainmentViewController
    private let interactions: StoryInteraction
    private let chatInteraction: ChatInteraction
    
    private let disposable = MetaDisposable()
    private let updatesDisposable = MetaDisposable()
    private var overlayTimer: SwiftSignalKit.Timer?
    
    init(context: AccountContext, stories: StoryListContext, initialId: StoryInitialIndex?) {
        self.entertainment = EntertainmentViewController(size: NSMakeSize(350, 350), context: context, mode: .stories, presentation: storyTheme)
        self.interactions = StoryInteraction()
        self.context = context
        self.initialId = initialId
        self.stories = stories
        self.chatInteraction = ChatInteraction(chatLocation: .peer(PeerId(0)), context: context)
        super.init()
        self._frameRect = context.window.contentView!.bounds
        self.bar = .init(height: 0)
        self.entertainment.loadViewIfNeeded()
    }
    
    override var dynamicSize: Bool {
        return true
    }
    
    override func measure(size: NSSize) {
        self.modal?.resize(with: size, animated: false)
    }
    
    override func viewClass() -> AnyClass {
        return StoryViewController.self
    }
    
    override var cornerRadius: CGFloat {
        return 0
    }
    
    func notify(with value: Any, oldValue: Any, animated: Bool) {
        if let value = value as? ChatPresentationInterfaceState {
            self.interactions.update({ current in
                var current = current
                if let entryId = current.entryId {
                    current.inputs[entryId] = value.effectiveInput
                }
                return current
            })
        }
        if let value = value as? StoryInteraction.State {
            self.chatInteraction.update({
                $0.withUpdatedEffectiveInputState(value.input)
            })
        }
    }
    
    func isEqual(to other: Notifable) -> Bool {
        return self === other as? StoryModalController
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        let context = self.context
        let initialId = self.initialId
        let chatInteraction = self.chatInteraction
        let interactions = self.interactions
        
        let stories = self.stories
        
        
        self.chatInteraction.add(observer: self)
        interactions.add(observer: self)
        
        let arguments = StoryArguments(context: context, interaction: self.interactions, chatInteraction: chatInteraction, showEmojiPanel: { [weak self] control in
            if let panel = self?.entertainment {
                showPopover(for: control, with: panel, edge: .maxX, inset:NSMakePoint(0 + 38, 10), delayBeforeShown: 0.1)
            }
        }, showReactionsPanel: { [weak interactions, weak self] control in
            if let entryId = interactions?.presentation.entryId {
                _ = storyReactions(context: context, peerId: entryId, react: { [weak self] reaction in
                    self?.genericView.playReaction(reaction)
                    self?.genericView.showTooltip(.reaction(reaction))
                }, onClose: {
                    self?.genericView.closeReactions()
                }).start(next: { view in
                    if let view = view {
                        self?.genericView.showReactions(view, control: control)
                    }
                })

            }
        }, attachPhotoOrVideo: { type in
            chatInteraction.attachPhotoOrVideo(type)
        }, attachFile: {
            chatInteraction.attachFile(false)
        }, nextStory: { [weak self] in
            self?.next()
        }, prevStory: { [weak self] in
            self?.previous()
        }, close: { [weak self] in
            self?.close()
        }, openPeerInfo: { [weak self] peerId in
            let controller = context.bindings.rootNavigation().controller as? PeerInfoController
            if peerId != context.peerId {
                if controller?.peerId != peerId {
                    context.bindings.rootNavigation().push(PeerInfoController(context: context, peerId: peerId))
                }
                self?.close()
            }
        }, openChat: { [weak self] peerId, messageId, initial in
            let controller = context.bindings.rootNavigation().controller as? ChatController
            if controller?.chatLocation.peerId != peerId {
                context.bindings.rootNavigation().push(ChatAdditionController(context: context, chatLocation: .peer(peerId), messageId: messageId, initialAction: initial))
            }
            self?.close()
        }, sendMessage: { [weak self] in
            self?.interactions.updateInput(with: "")
            self?.genericView.showTooltip(.text)
        }, toggleRecordType: { [weak self] in
            FastSettings.toggleRecordingState()
            self?.interactions.update { current in
                var current = current
                current.recordType = FastSettings.recordingState
                return current
            }
        }, deleteStory: { [weak self] storyId in
            confirm(for: context.window, information: "Are you sure you want to delete story?", successHandler: { _ in
                self?.stories.delete(id: storyId)
            }, appearance: storyTheme.appearance)
        })
        
        genericView.setArguments(arguments)
        interactions.add(observer: self.genericView)
        
        entertainment.update(with: chatInteraction)
        
        chatInteraction.sendAppFile = { [weak self] file, silent, query, schedule, collectionId in
            self?.genericView.showTooltip(.media([file]))
        }
        chatInteraction.sendPlainText = { [weak self] text in
            _ = self?.interactions.appendText(.makeEmojiHolder(text, fromRect: nil))
            self?.applyFirstResponder()
        }
        chatInteraction.appendAttributedText = { [weak self] attr in
            _ = self?.interactions.appendText(attr)
            self?.applyFirstResponder()
        }
        
        
       
        chatInteraction.showPreviewSender = { urls, asMedia, attributedString in
            var updated:[URL] = []
            for url in urls {
                if url.path.contains("/T/TemporaryItems/") {
                    let newUrl = URL(fileURLWithPath: NSTemporaryDirectory() + url.path.nsstring.lastPathComponent)
                    try? FileManager.default.moveItem(at: url, to: newUrl)
                    if FileManager.default.fileExists(atPath: newUrl.path) {
                        updated.append(newUrl)
                    }
                } else {
                    if FileManager.default.fileExists(atPath: url.path) {
                        updated.append(url)
                    }
                }
            }
            if !updated.isEmpty {
                showModal(with: PreviewSenderController(urls: updated, chatInteraction: chatInteraction, asMedia: asMedia, attributedString: attributedString, presentation: storyTheme), for: context.window)
            }
        }
        
        chatInteraction.sendMedias = { [weak self] medias, caption, isCollage, additionText, silent, atDate, isSpoiler in
            self?.genericView.showTooltip(.media(medias))
        }
        chatInteraction.attachFile = { value in
            filePanel(canChooseDirectories: true, for: context.window, appearance: storyTheme.appearance, completion:{ result in
                if let result = result {
                    
                    let previous = result.count
                    var exceedSize: Int64?
                    let result = result.filter { path -> Bool in
                        if let size = fileSize(path) {
                            let exceed = fileSizeLimitExceed(context: context, fileSize: size)
                            if exceed {
                                exceedSize = size
                            }
                            return exceed
                        }
                        return false
                    }
                    
                    let afterSizeCheck = result.count
                    
                    if afterSizeCheck == 0 && previous != afterSizeCheck {
                        showFileLimit(context: context, fileSize: exceedSize)
                    } else {
                        chatInteraction.showPreviewSender(result.map{URL(fileURLWithPath: $0)}, false, nil)
                    }
                    
                }
            })
        }
        
        chatInteraction.attachPhotoOrVideo = { type in
            var exts:[String] = mediaExts
            if let type = type {
                switch type {
                case .photo:
                    exts = photoExts
                case .video:
                    exts = videoExts
                }
            }
            filePanel(with: exts, canChooseDirectories: true, for: context.window, appearance: storyTheme.appearance, completion:{ result in
                if let result = result {
                    let previous = result.count
                    var exceedSize: Int64?
                    let result = result.filter { path -> Bool in
                        if let size = fileSize(path) {
                            let exceed = fileSizeLimitExceed(context: context, fileSize: size)
                            if exceed {
                                exceedSize = size
                            }
                            return exceed
                        }
                        return false
                    }
                    let afterSizeCheck = result.count
                    if afterSizeCheck == 0 && previous != afterSizeCheck {
                        showFileLimit(context: context, fileSize: exceedSize)
                    } else {
                        chatInteraction.showPreviewSender(result.map(URL.init(fileURLWithPath:)), true, nil)
                    }
                }
            })
        }

        
        let signal = stories.state |> deliverOnMainQueue

        disposable.set(signal.start(next: { [weak self] state in
            let items = state.itemSets.filter { !$0.items.isEmpty }
            if items.isEmpty {
                self?.initialId = nil
                self?.close()
            } else {
                self?.genericView.update(context: context, items: items, initial: initialId)
                self?.readyOnce()
            }
        }))
        
        
        self.overlayTimer = SwiftSignalKit.Timer(timeout: 30 / 1000, repeat: true, completion: { [weak self] in
            DispatchQueue.main.async {
                self?.interactions.update { current in
                    var current = current
                    current.hasPopover = hasPopover(context.window)
                    current.hasMenu = contextMenuOnScreen()
                    current.hasModal = findModal(PreviewSenderController.self) != nil || findModal(InputDataModalController.self) != nil
                    return current
                }
            }
        }, queue: .concurrentDefaultQueue())
        
        self.overlayTimer?.start()
        
        updatesDisposable.set(context.window.keyWindowUpdater.start(next: { [weak interactions] windowIsKey in
            interactions?.update({ current in
                var current = current
                current.windowIsKey = windowIsKey
                return current
            })
        }))
        
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        let context = self.context
        
        window?.set(handler: { [weak self] _ in
            return self?.previous() ?? .invoked
        }, with: self, for: .LeftArrow, priority: .modal)
        
        window?.set(handler: { [weak self] _ in
            return self?.next() ?? .invoked
        }, with: self, for: .RightArrow, priority: .modal)
        
        window?.set(handler: { [weak self] _ in
            return self?.delete() ?? .invoked
        }, with: self, for: .Delete, priority: .modal)
        
        window?.set(handler: { [weak self] _ in
            guard self?.genericView.isInputFocused == false else {
                return .rejected
            }
            self?.interactions.update { current in
                var current = current
                if current.isPaused {
                    current.isSpacePaused = false
                } else {
                    current.isSpacePaused = !current.isSpacePaused
                }
                return current
            }
            return .invoked
        }, with: self, for: .Space, priority: .modal)
        
        
        window?.set(handler: { [weak self] _ in
            guard self?.genericView.isTextEmpty == true else {
                return .rejected
            }
            self?.interactions.startRecording(context: context, autohold: true)
            return .invoked
        }, with: self, for: .R, priority: .modal, modifierFlags: [.command])
        
        window?.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.genericView.inputTextView?.boldWord()
            return .invoked
        }, with: self, for: .B, priority: .modal, modifierFlags: [.command])
        
        window?.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.genericView.inputTextView?.underlineWord()
            return .invoked
        }, with: self, for: .U, priority: .modal, modifierFlags: [.shift, .command])
        
        window?.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.genericView.inputTextView?.spoilerWord()
            return .invoked
        }, with: self, for: .P, priority: .modal, modifierFlags: [.shift, .command])
        
        window?.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.genericView.inputTextView?.strikethroughWord()
            return .invoked
        }, with: self, for: .X, priority: .modal, modifierFlags: [.shift, .command])
        
        window?.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.genericView.inputTextView?.removeAllAttributes()
            return .invoked
        }, with: self, for: .Backslash, priority: .modal, modifierFlags: [.command])
        
        window?.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.genericView.makeUrl()
            return .invoked
        }, with: self, for: .U, priority: .modal, modifierFlags: [.command])
        
        window?.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.genericView.inputTextView?.italicWord()
            return .invoked
        }, with: self, for: .I, priority: .modal, modifierFlags: [.command])
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        window?.removeObserver(for: self)
    }
    
    override func escapeKeyAction() -> KeyHandlerResult {
        if let _ = interactions.presentation.inputRecording {
           interactions.update { current in
               var current = current
               current.inputRecording = nil
               return current
           }
           return .invoked
       } else if interactions.presentation.readingText {
            interactions.update { current in
                var current = current
                current.readingText = false
                return current
            }
            return .invoked
        } else if let _ = interactions.presentation.inputRecording {
            interactions.update { current in
                var current = current
                current.inputRecording = nil
                return current
            }
            return .invoked
        } else if self.genericView.inputView == window?.firstResponder {
            self.genericView.resetInputView()
            return .invoked
        } else if interactions.presentation.hasReactions {
            self.genericView.closeReactions()
            return .invoked
        } else {
            return super.escapeKeyAction()
        }
    }
    
    @discardableResult private func previous() -> KeyHandlerResult {
        return genericView.previous()
    }
    @discardableResult private func next() -> KeyHandlerResult {
        return genericView.next()
    }
    @discardableResult private func delete() -> KeyHandlerResult {
        return genericView.delete()
    }
    
    
    deinit {
        disposable.dispose()
        updatesDisposable.dispose()
    }
    
    override var containerBackground: NSColor {
        return .clear
    }
    
    private var genericView: StoryViewController {
        return self.view as! StoryViewController
    }
    
    override func firstResponder() -> NSResponder? {
        return self.genericView.inputView
    }
    
    private func applyFirstResponder() {
        _ = self.window?.makeFirstResponder(self.firstResponder())
    }
    
    override func becomeFirstResponder() -> Bool? {
        return false
    }
    
    override func close(animationType: ModalAnimationCloseBehaviour = .common) {
        super.close(animationType: .common)
        genericView.animateDisappear(initialId)
    }

    override var isVisualEffectBackground: Bool {
        return true
    }
    
    static func ShowStories(context: AccountContext, stories: StoryListContext, initialId: StoryInitialIndex?) {
        showModal(with: StoryModalController(context: context, stories: stories, initialId: initialId), for: context.window, animationType: .animateBackground)
    }
}



