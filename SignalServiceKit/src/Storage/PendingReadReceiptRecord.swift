//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public struct PendingReadReceiptRecord: Codable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "pending_read_receipts"

    public private(set) var id: Int64?
    public let threadId: Int64
    public let messageTimestamp: Int64
    public let messageUniqueId: String?
    public let authorUuid: String?
    public let authorPhoneNumber: String?

    public init(threadId: Int64, messageTimestamp: Int64, messageUniqueId: String?, authorPhoneNumber: String?, authorUuid: String?) {
        self.threadId = threadId
        self.messageTimestamp = messageTimestamp
        self.messageUniqueId = messageUniqueId
        self.authorUuid = authorUuid
        self.authorPhoneNumber = (authorUuid == nil) ? authorPhoneNumber : nil
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(Int64.self, forKey: .id)
        self.threadId = try container.decode(Int64.self, forKey: .threadId)
        self.messageTimestamp = try container.decode(Int64.self, forKey: .messageTimestamp)
        self.messageUniqueId = try container.decodeIfPresent(String.self, forKey: .messageUniqueId)
        self.authorUuid = try container.decodeIfPresent(String.self, forKey: .authorUuid)
        self.authorPhoneNumber = (self.authorUuid == nil) ? try container.decodeIfPresent(String.self, forKey: .authorPhoneNumber) : nil
    }

    mutating public func didInsert(with rowID: Int64, for column: String?) {
        self.id = rowID
    }
}
