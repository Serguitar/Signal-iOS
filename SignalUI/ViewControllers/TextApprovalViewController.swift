//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

public protocol TextApprovalViewControllerDelegate: AnyObject {

    func textApproval(_ textApproval: TextApprovalViewController, didApproveMessage messageBody: MessageBody?, linkPreviewDraft: OWSLinkPreviewDraft?)

    func textApprovalDidCancel(_ textApproval: TextApprovalViewController)

    func textApprovalCustomTitle(_ textApproval: TextApprovalViewController) -> String?

    func textApprovalRecipientsDescription(_ textApproval: TextApprovalViewController) -> String?

    func textApprovalMode(_ textApproval: TextApprovalViewController) -> ApprovalMode
}

// MARK: -

public class TextApprovalViewController: OWSViewController, BodyRangesTextViewDelegate {

    public weak var delegate: TextApprovalViewControllerDelegate?

    // MARK: - Properties

    private let initialMessageBody: MessageBody
    private let linkPreviewFetcher: LinkPreviewFetcher

    private let textView = BodyRangesTextView()
    private let footerView = ApprovalFooterView()
    private var bottomConstraint: NSLayoutConstraint?

    private lazy var inputAccessoryPlaceholder: InputAccessoryViewPlaceholder = {
        let placeholder = InputAccessoryViewPlaceholder()
        placeholder.delegate = self
        placeholder.referenceView = view
        return placeholder
    }()

    private var approvalMode: ApprovalMode {
        guard let delegate = delegate else {
            return .send
        }
        return delegate.textApprovalMode(self)
    }

    // MARK: - Initializers

    required public init(messageBody: MessageBody) {
        self.initialMessageBody = messageBody
        self.linkPreviewFetcher = LinkPreviewFetcher(
            linkPreviewManager: Self.linkPreviewManager,
            schedulers: DependenciesBridge.shared.schedulers
        )

        super.init()

        self.linkPreviewFetcher.onStateChange = { [weak self] in self?.updateLinkPreviewView() }
    }

    // MARK: - UIViewController

    public override var canBecomeFirstResponder: Bool {
        return true
    }

    var currentInputAcccessoryView: UIView?

    public override var inputAccessoryView: UIView? {
        return inputAccessoryPlaceholder
    }

    // MARK: - View Lifecycle

    override public func viewDidLoad() {
        super.viewDidLoad()

        if let title = delegate?.textApprovalCustomTitle(self) {
            self.navigationItem.title = title
        } else {
            self.navigationItem.title = OWSLocalizedString("MESSAGE_APPROVAL_DIALOG_TITLE",
                                                          comment: "Title for the 'message approval' dialog.")
        }

        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelPressed))

        footerView.delegate = self

        // Don't allow interactive dismissal.
        isModalInPresentation = true
    }

    private func updateSendButton() {
        guard
            !textView.isEmpty,
            let recipientsDescription = delegate?.textApprovalRecipientsDescription(self)
        else {
            footerView.isHidden = true
            return
        }
        footerView.setNamesText(recipientsDescription, animated: false)
        footerView.isHidden = false
    }

    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        updateSendButton()
        updateLinkPreviewText()

        textView.becomeFirstResponder()
    }

    // MARK: - Link Previews

    private lazy var linkPreviewView: LinkPreviewView = {
        let linkPreviewView = LinkPreviewView(draftDelegate: self)
        linkPreviewView.isHidden = true
        return linkPreviewView
    }()

    private func updateLinkPreviewText() {
        linkPreviewFetcher.update(textView.messageBodyForSending.text)
    }

    private func updateLinkPreviewView() {
        switch linkPreviewFetcher.currentState {
        case .none, .failed:
            linkPreviewView.isHidden = true
        case .loading:
            linkPreviewView.configureForNonCVC(state: LinkPreviewLoading(linkType: .preview), isDraft: true)
            linkPreviewView.isHidden = false
        case .loaded(let linkPreviewDraft):
            linkPreviewView.configureForNonCVC(state: LinkPreviewDraft(linkPreviewDraft: linkPreviewDraft), isDraft: true)
            linkPreviewView.isHidden = false
        }
    }

    // MARK: - Create Views

    public override func loadView() {

        self.view = UIView.container()
        self.view.backgroundColor = Theme.backgroundColor

        let stackView = UIStackView(arrangedSubviews: [linkPreviewView, textView, footerView])
        stackView.axis = .vertical
        view.addSubview(stackView)
        stackView.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        stackView.autoPinEdge(toSuperviewSafeArea: .leading)
        stackView.autoPinEdge(toSuperviewSafeArea: .trailing)
        bottomConstraint = stackView.autoPinEdge(toSuperviewEdge: .bottom)

        // Text View
        textView.mentionDelegate = self
        textView.backgroundColor = Theme.backgroundColor
        textView.textColor = Theme.primaryTextColor
        textView.font = UIFont.dynamicTypeBody
        textView.setMessageBody(self.initialMessageBody, txProvider: DependenciesBridge.shared.db.readTxProvider)
        textView.contentInset = UIEdgeInsets(top: 0.0, left: 0.0, bottom: 0.0, right: 0.0)
        textView.textContainerInset = UIEdgeInsets(top: 10.0, left: 10.0, bottom: 10.0, right: 10.0)
    }

    // MARK: - Event Handlers

    @objc
    private func cancelPressed(sender: UIButton) {
        delegate?.textApprovalDidCancel(self)
    }

    // MARK: - UITextViewDelegate

    public func textViewDidChange(_ textView: UITextView) {
        updateSendButton()
        updateLinkPreviewText()
    }

    public func textViewDidBeginTypingMention(_ textView: BodyRangesTextView) {}

    public func textViewDidEndTypingMention(_ textView: BodyRangesTextView) {}

    public func textViewMentionPickerParentView(_ textView: BodyRangesTextView) -> UIView? {
        return nil
    }

    public func textViewMentionPickerReferenceView(_ textView: BodyRangesTextView) -> UIView? {
        return nil
    }

    public func textViewMentionPickerPossibleAddresses(_ textView: BodyRangesTextView, tx: DBReadTransaction) -> [SignalServiceAddress] {
        return []
    }

    public func textViewDisplayConfiguration(_ textView: BodyRangesTextView) -> HydratedMessageBody.DisplayConfiguration {
        return .composing()
    }

    public func mentionPickerStyle(_ textView: BodyRangesTextView) -> MentionPickerStyle {
        return .default
    }

    // We want to invalidate the cache but reuse it within this same controller.
    private let mentionCacheInvalidationKey = UUID().uuidString

    public func textViewMentionCacheInvalidationKey(_ textView: BodyRangesTextView) -> String {
        return mentionCacheInvalidationKey
    }
}

// MARK: -

extension TextApprovalViewController: ApprovalFooterDelegate {
    public func approvalFooterDelegateDidRequestProceed(_ approvalFooterView: ApprovalFooterView) {
        let linkPreviewDraft = linkPreviewFetcher.linkPreviewDraftIfLoaded
        delegate?.textApproval(self, didApproveMessage: self.textView.messageBodyForSending, linkPreviewDraft: linkPreviewDraft)
    }

    public func approvalMode(_ approvalFooterView: ApprovalFooterView) -> ApprovalMode {
        return approvalMode
    }

    public func approvalFooterDidBeginEditingText() {}
}

// MARK: -

extension TextApprovalViewController: InputAccessoryViewPlaceholderDelegate {
    public func inputAccessoryPlaceholderKeyboardIsPresenting(animationDuration: TimeInterval, animationCurve: UIView.AnimationCurve) {
        handleKeyboardStateChange(animationDuration: animationDuration, animationCurve: animationCurve)
    }

    public func inputAccessoryPlaceholderKeyboardDidPresent() {
        updateFooterViewPosition()
    }

    public func inputAccessoryPlaceholderKeyboardIsDismissing(animationDuration: TimeInterval, animationCurve: UIView.AnimationCurve) {
        handleKeyboardStateChange(animationDuration: animationDuration, animationCurve: animationCurve)
    }

    public func inputAccessoryPlaceholderKeyboardDidDismiss() {
        updateFooterViewPosition()
    }

    public func inputAccessoryPlaceholderKeyboardIsDismissingInteractively() {
        updateFooterViewPosition()
    }

    func handleKeyboardStateChange(animationDuration: TimeInterval, animationCurve: UIView.AnimationCurve) {
        guard animationDuration > 0 else { return updateFooterViewPosition() }

        UIView.animate(
            withDuration: animationDuration,
            delay: 0,
            options: animationCurve.asAnimationOptions,
            animations: { [self] in
                updateFooterViewPosition()
            }
        )
    }

    func updateFooterViewPosition() {
        bottomConstraint?.constant = -inputAccessoryPlaceholder.keyboardOverlap

        // We always want to apply the new bottom bar position immediately,
        // as this only happens during animations (interactive or otherwise)
        view.layoutIfNeeded()
    }
}

// MARK: -

extension TextApprovalViewController: LinkPreviewViewDraftDelegate {
    public func linkPreviewDidCancel() {
        linkPreviewFetcher.disable()
    }
}
