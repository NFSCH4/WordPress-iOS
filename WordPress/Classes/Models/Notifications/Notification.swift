import Foundation
import CoreData
import Simperium



// MARK: - Notification Entity
//
@objc(Notification)
class Notification: SPManagedObject
{
    /// Associated Resource's Icon, as a plain string
    ///
    @NSManaged var icon: String?

    /// Noticon resource, associated with this notification
    ///
    @NSManaged var noticon: String?

    /// Indicates whether the note was already read, or not
    ///
    @NSManaged var read: NSNumber?

    /// Timestamp as a String
    ///
    @NSManaged var timestamp: String?

    /// Notification Type
    ///
    @NSManaged var type: String?

    /// Associated Resource's URL
    ///
    @NSManaged var url: String?

    /// Plain Title ("1 Like" / Etc)
    ///
    @NSManaged var title: String?

    /// Raw Subject Blocks
    ///
    @NSManaged var subject: [AnyObject]?

    /// Raw Header Blocks
    ///
    @NSManaged var header: [AnyObject]?

    /// Raw Body Blocks
    ///
    @NSManaged var body: [AnyObject]?

    /// Raw Associated Metadata
    ///
    @NSManaged var meta: NSDictionary?

    /// Timestamp As Date Transient Storage.
    ///
    private var cachedTimestampAsDate: NSDate?

    /// Subject Blocks Transient Storage.
    ///
    private var cachedSubjectBlockGroup: NotificationBlockGroup?

    /// Header Blocks Transient Storage.
    ///
    private var cachedHeaderBlockGroup: NotificationBlockGroup?

    /// Body Blocks Transient Storage.
    ///
    private var cachedBodyBlockGroups: [NotificationBlockGroup]?

    /// Known kinds of Notifications
    ///
    enum Kind: String {
        case Comment        = "comment"
        case CommentLike    = "comment_like"
        case Follow         = "follow"
        case Like           = "like"
        case Matcher        = "automattcher"
        case Post           = "post"
        case User           = "user"
        case Unknown        = "unknown"

        var toTypeValue: String {
            return rawValue
        }
    }



    /// Nukes any cached values.
    ///
    override func didTurnIntoFault() {
        cachedTimestampAsDate = nil
        cachedSubjectBlockGroup = nil
        cachedHeaderBlockGroup = nil
        cachedBodyBlockGroups = nil
    }

    // This is a NO-OP that will force NSFetchedResultsController to reload the row for this object.
    // Helpful when dealing with transient attributes.
    //
    func didChangeOverrides() {
        let readValue = read
        read = readValue
    }

    /// Returns the first BlockGroup of the specified type, if any.
    ///
    func blockGroupOfType(type: NoteBlockGroupType) -> NotificationBlockGroup? {
        for blockGroup in bodyBlockGroups where blockGroup.type == type {
            return blockGroup
        }

        return nil
    }

    /// Attempts to find the Notification Range associated with a given URL.
    ///
    func notificationRangeWithUrl(url: NSURL) -> NotificationRange? {
        var groups = bodyBlockGroups
        if let headerBlockGroup = headerBlockGroup {
            groups.append(headerBlockGroup)
        }

        let blocks = groups.flatMap { $0.blocks }
        for block in blocks {
            if let range = block.notificationRangeWithUrl(url) {
                return range
            }
        }

        return nil
    }
}



// MARK: - Notification Computed Properties
//
extension Notification
{
    /// Verifies if the current notification is actually a Badge one.
    ///
    var isBadge: Bool {
        //  Note: This developer does not like duck typing. Sorry about the following snippet.
        //
        let blocks = bodyBlockGroups.flatMap { $0.blocks }
        for block in blocks {
            for media in block.media where media.isBadge {
                return true
            }
        }

        return false
    }

    /// Verifies if the current notification is a Comment-Y note, and if it has been replied to.
    ///
    var isRepliedComment: Bool {
        return isComment == true && metaReplyID != nil
    }

    //// Check if this note is a comment and in 'Unapproved' status
    ///
    var isUnapprovedComment: Bool {
        guard let block = blockGroupOfType(.Comment)?.blockOfType(.Comment) else {
            return false
        }

        return block.isActionEnabled(.Approve) && !block.isActionOn(.Approve)
    }

    /// Parses the Notification.type field into a Swift Native enum. Returns .Unknown on failure.
    ///
    var kind: Kind {
        guard let type = type, let kind = Kind(rawValue: type) else {
            return .Unknown
        }
        return kind
    }

    // TODO: Nuke when NotificationBlock is Swifted
    var isComment: Bool {
        return kind == .Comment
    }

    // TODO: Nuke when NotificationBlock is Swifted
    var isCommentLike: Bool {
        return kind == .CommentLike
    }

    // TODO: Nuke when NotificationBlock is Swifted
    var isFollow: Bool {
        return kind == .Follow
    }

    // TODO: Nuke when NotificationBlock is Swifted
    var isLike: Bool {
        return kind == .Like
    }

    // TODO: Nuke when NotificationBlock is Swifted
    var isMatcher: Bool {
        return kind == .Matcher
    }

    // TODO: Nuke when NotificationBlock is Swifted
    var isPost: Bool {
        return kind == .Post
    }

    /// Returns the Meta ID's collection, if any.
    ///
    private var metaIds: [String: AnyObject]? {
        return meta?[MetaKeys.Ids] as? [String: AnyObject]
    }

    /// Comment ID, if any.
    ///
    var metaCommentID: NSNumber? {
        return metaIds?[MetaKeys.Comment] as? NSNumber
    }

    /// Post ID, if any.
    ///
    var metaPostID: NSNumber? {
        return metaIds?[MetaKeys.Post] as? NSNumber
    }

    /// Comment Reply ID, if any.
    ///
    var metaReplyID: NSNumber? {
        return metaIds?[MetaKeys.Reply] as? NSNumber
    }

    /// Site ID, if any.
    ///
    var metaSiteID: NSNumber? {
        return metaIds?[MetaKeys.Site] as? NSNumber
    }

    /// Icon URL
    ///
    var iconURL: NSURL? {
        guard let rawIconURL = icon, let iconURL = NSURL(string: rawIconURL) else {
            return nil
        }

        return iconURL
    }

    /// Associated Resource URL
    ///
    var resourceURL: NSURL? {
        guard let rawURL = url, let resourceURL = NSURL(string: rawURL) else {
            return nil
        }

        return resourceURL
    }

    /// Parse the Timestamp as a Cocoa Date Instance.
    ///
    var timestampAsDate: NSDate {
        assert(timestamp != nil, "Notification Timestamp should not be nil [\(simperiumKey)]")

        if let timestampAsDate = cachedTimestampAsDate {
            return timestampAsDate
        }
        guard let timestamp = timestamp, let timestampAsDate = NSDate.dateWithISO8601String(timestamp) else {
            DDLogSwift.logError("Error: couldn't parse date [\(self.timestamp)] for notification with id [\(simperiumKey)]")
            return NSDate()
        }

        cachedTimestampAsDate = timestampAsDate
        return timestampAsDate
    }

    /// Returns the Subject Block Group, if any.
    ///
    var subjectBlockGroup: NotificationBlockGroup? {
        if let subjectBlockGroup = cachedSubjectBlockGroup {
            return subjectBlockGroup
        }

        cachedSubjectBlockGroup = NotificationBlockGroup.subjectGroupFromArray(subject, notification: self)
        return cachedSubjectBlockGroup
    }

    /// Returns the Header Block Group, if any.
    ///
    var headerBlockGroup: NotificationBlockGroup? {
        if let headerBlockGroup = cachedHeaderBlockGroup {
            return headerBlockGroup
        }

        cachedHeaderBlockGroup = NotificationBlockGroup.headerGroupFromArray(header, notification: self)
        return cachedHeaderBlockGroup
    }

    /// Returns the Body Block Groups, if any.
    ///
    var bodyBlockGroups: [NotificationBlockGroup] {
        if let bodyBlockGroups = cachedBodyBlockGroups {
            return bodyBlockGroups
        }

        let bodyBlockGroups = NotificationBlockGroup.bodyGroupsFromArray(body, notification: self)
        cachedBodyBlockGroups = bodyBlockGroups
        return bodyBlockGroups
    }

    /// Returns the Subject Block, if any.
    ///
    var subjectBlock: NotificationBlock? {
        return subjectBlockGroup?.blocks.first
    }

    /// Returns the Snippet Block, if any.
    ///
    var snippetBlock: NotificationBlock? {
        guard let subjectBlocks = subjectBlockGroup?.blocks where subjectBlocks.count > 1 else {
            return nil
        }

        return subjectBlocks.last
    }
}


// MARK: - Private Constants
//
private extension Notification
{
    /// Meta Field Parsing-Keys
    ///
    private enum MetaKeys {
        static let Ids      = "ids"
        static let Site     = "site"
        static let Post     = "post"
        static let Comment  = "comment"
        static let Reply    = "reply_comment"
    }
}
