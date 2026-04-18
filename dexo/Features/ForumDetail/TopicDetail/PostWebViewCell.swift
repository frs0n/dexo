import UIKit

protocol PostCellDelegate: AnyObject {
    func postCell(didTapImageURL url: URL, inPostId postId: Int)
    func postCell(didTapLinkURL url: URL)
    func postCell(didTapShowRepliesForPostId postId: Int)
    func postCell(didTapToggleDetails detailsIndex: Int, postId: Int)
    func postCell(didTapReplyToPost post: DiscourseTopicDetail.Post)
    func postCell(didToggleBookmarkForPost post: DiscourseTopicDetail.Post, isBookmarked: Bool)
    func postCell(didTapAvatarForUsername username: String)
    func postCell(didTapReaction reactionId: String, forPost post: DiscourseTopicDetail.Post)
    func postCell(didToggleLikeForPost post: DiscourseTopicDetail.Post, liked: Bool)
    func postCell(didTapBoostForPost post: DiscourseTopicDetail.Post)
    func postCell(didTapDeleteBoost boost: DiscourseTopicDetail.Boost)
    func postCell(didTapToggleBoostsForPost post: DiscourseTopicDetail.Post, sourceView: UIView)
    func postCell(didVotePoll pollName: String, options: [String], forPost post: DiscourseTopicDetail.Post)
    func postCell(didRemovePollVote pollName: String, forPost post: DiscourseTopicDetail.Post)
    func postCell(didTapFlagPost post: DiscourseTopicDetail.Post)
    func postCell(didLongPressPost post: DiscourseTopicDetail.Post)
}
