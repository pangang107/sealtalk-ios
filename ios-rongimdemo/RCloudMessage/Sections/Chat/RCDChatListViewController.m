//
//  FirstViewController.m
//  RongCloud
//
//  Created by Liv on 14/10/31.
//  Copyright (c) 2014年 RongCloud. All rights reserved.
//

#import "RCDChatListViewController.h"
#import "KxMenu.h"
#import "RCDAddressBookViewController.h"
#import "RCDChatListCell.h"
#import "RCDChatViewController.h"
#import "RCDContactSelectedTableViewController.h"
#import "RCDSearchBar.h"
#import "RCDSearchViewController.h"
#import "RCDUIBarButtonItem.h"
#import "UIColor+RCColor.h"
#import <SDWebImage/UIImageView+WebCache.h>
#import "UITabBar+badge.h"
#import "RCDSearchFriendController.h"
#import "RCDCommonString.h"
#import "RCDUserInfoManager.h"
#import "RCDLoginManager.h"
#import "RCDGroupNotificationMessage.h"
#import "RCDContactNotificationMessage.h"
@interface RCDChatListViewController () <UISearchBarDelegate, RCDSearchViewDelegate>
@property (nonatomic, strong) UINavigationController *searchNavigationController;
@property (nonatomic, strong) UIView *headerView;
@property (nonatomic, strong) RCDSearchBar *searchBar;
@property (nonatomic, assign) NSUInteger index;
@property (nonatomic, assign) BOOL isClick;
@end

@implementation RCDChatListViewController
#pragma mark - life cycle
- (id)init {
    self = [super init];
    if (self) {
        //设置要显示的会话类型
        [self setDisplayConversationTypes:@[@(ConversationType_PRIVATE), @(ConversationType_APPSERVICE), @(ConversationType_PUBLICSERVICE), @(ConversationType_GROUP), @(ConversationType_SYSTEM)]];

        //聚合会话类型
        [self setCollectionConversationType:@[@(ConversationType_SYSTEM)]];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self initSubviews];
    [self setTabBarStyle];
    [self registerNotification];
    [self checkVersion];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.searchBar.frame = CGRectMake(0, 0, self.conversationListTableView.frame.size.width, 44);
    [self updateBadgeValueForTabBarItem];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.isClick = YES;
    [self setNaviItem];
    RCUserInfo *groupNotify = [[RCUserInfo alloc] initWithUserId:@"__system__" name:@"" portrait:nil];
    [[RCIM sharedRCIM] refreshUserInfoCache:groupNotify withUserId:@"__system__"];
}

#pragma mark - UISearchBarDelegate
- (void)searchBarTextDidBeginEditing:(UISearchBar *)searchBar {
    [self.navigationController setNavigationBarHidden:YES animated:YES];
    RCDSearchViewController *searchViewController = [[RCDSearchViewController alloc] init];
    self.searchNavigationController = [[UINavigationController alloc] initWithRootViewController:searchViewController];
    searchViewController.delegate = self;
    [self.navigationController.view addSubview:self.searchNavigationController.view];
}

#pragma mark - RCDSearchViewDelegate
- (void)searchViewControllerDidClickCancel {
    [self.searchNavigationController.view removeFromSuperview];
    [self.searchNavigationController removeFromParentViewController];
    [self.navigationController setNavigationBarHidden:NO animated:YES];
    [self refreshConversationTableViewIfNeeded];
}

#pragma mark - UIScrollViewDelegate
- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    NSIndexPath *indexPath = [self.conversationListTableView indexPathForRowAtPoint:scrollView.contentOffset];
    self.index = indexPath.row;
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    //恢复conversationListTableView的自动回滚功能。
    self.conversationListTableView.contentInset = UIEdgeInsetsMake(0, 0, 0, 0);
}

#pragma mark - over method
/**
 *  点击进入会话页面
 *
 *  @param conversationModelType 会话类型
 *  @param model                 会话数据
 *  @param indexPath             indexPath description
 */
- (void)onSelectedTableRow:(RCConversationModelType)conversationModelType
         conversationModel:(RCConversationModel *)model
               atIndexPath:(NSIndexPath *)indexPath {
    if (self.isClick) {
        self.isClick = NO;

        if (model.conversationModelType == RC_CONVERSATION_MODEL_TYPE_PUBLIC_SERVICE || conversationModelType == RC_CONVERSATION_MODEL_TYPE_NORMAL) {
            [self pushChatVC:model];
            return;
        }
        //聚合会话类型，此处自定设置。
        if (conversationModelType == RC_CONVERSATION_MODEL_TYPE_COLLECTION) {
            RCDChatListViewController *temp = [[RCDChatListViewController alloc] init];
            NSArray *array = [NSArray arrayWithObject:[NSNumber numberWithInt:model.conversationType]];
            [temp setDisplayConversationTypes:array];
            [temp setCollectionConversationType:nil];
            temp.isEnteredToCollectionViewController = YES;
            [self.navigationController pushViewController:temp animated:YES];
        }

        //自定义会话类型
        if (conversationModelType == RC_CONVERSATION_MODEL_TYPE_CUSTOMIZATION) {
            if ([model.objectName isEqualToString:@"ST:ContactNtf"] || [model.objectName isEqualToString:RCContactNotificationMessageIdentifier]) {
                [self pushAddressBook];
            }
        }
    }
}

//*********************插入自定义Cell*********************//
//插入自定义会话model
- (NSMutableArray *)willReloadTableData:(NSMutableArray *)dataSource {
    for (int i = 0; i < dataSource.count; i++) {
        RCConversationModel *model = dataSource[i];
        //筛选请求添加好友的系统消息，用于生成自定义会话类型的cell
        if (model.conversationType == ConversationType_SYSTEM &&
            ([model.lastestMessage isMemberOfClass:[RCDContactNotificationMessage class]] || [model.lastestMessage isMemberOfClass:[RCContactNotificationMessage class]])) {
            model.conversationModelType = RC_CONVERSATION_MODEL_TYPE_CUSTOMIZATION;
        }
        if ([model.lastestMessage isKindOfClass:[RCGroupNotificationMessage class]]) {
            RCGroupNotificationMessage *groupNotification = (RCGroupNotificationMessage *)model.lastestMessage;
            if ([groupNotification.operation isEqualToString:@"Quit"]) {
                NSData *jsonData = [groupNotification.data dataUsingEncoding:NSUTF8StringEncoding];
                NSDictionary *dictionary =
                [NSJSONSerialization JSONObjectWithData:jsonData options:NSJSONReadingMutableContainers error:nil];
                NSDictionary *data =
                [dictionary[@"data"] isKindOfClass:[NSDictionary class]] ? dictionary[@"data"] : nil;
                NSString *nickName =
                [data[@"operatorNickname"] isKindOfClass:[NSString class]] ? data[@"operatorNickname"] : nil;
                if ([nickName isEqualToString:[RCIM sharedRCIM].currentUserInfo.name]) {
                    [[RCIMClient sharedRCIMClient] removeConversation:model.conversationType targetId:model.targetId];
                    [self refreshConversationTableViewIfNeeded];
                }
            }
        }
    }
    return dataSource;
}

//左滑删除
- (void)rcConversationListTableView:(UITableView *)tableView
                 commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
                  forRowAtIndexPath:(NSIndexPath *)indexPath {
    //可以从数据库删除数据
    RCConversationModel *model = self.conversationListDataSource[indexPath.row];
    [[RCIMClient sharedRCIMClient] removeConversation:ConversationType_SYSTEM targetId:model.targetId];
    [self.conversationListDataSource removeObjectAtIndex:indexPath.row];
    [self.conversationListTableView reloadData];
}

//高度
- (CGFloat)rcConversationListTableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 67.0f;
}

//自定义cell
- (RCConversationBaseCell *)rcConversationListTableView:(UITableView *)tableView
                                  cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    RCConversationModel *model = self.conversationListDataSource[indexPath.row];
    RCDChatListCell *cell = [RCDChatListCell cellWithTableView:tableView];
    [cell setDataModel:model];
    return cell;
}
//*********************插入自定义Cell*********************//

//点击头像功能和点击cell功能同步
- (void)didTapCellPortrait:(RCConversationModel *)model {
    [self onSelectedTableRow:model.conversationModelType conversationModel:model atIndexPath:nil];
}

/*
 //会话有新消息通知的时候显示数字提醒，设置为NO,不显示数字只显示红点
 -(void)willDisplayConversationTableCell:(RCConversationBaseCell *)cell
 atIndexPath:(NSIndexPath *)indexPath
 {
 RCConversationModel *model=
 self.conversationListDataSource[indexPath.row];
 if (model.conversationType == ConversationType_PRIVATE) {
 ((RCConversationCell *)cell).isShowNotificationNumber = NO;
 }
 }
 */

- (void)notifyUpdateUnreadMessageCount {
    [self updateBadgeValueForTabBarItem];
}

//收到消息监听
- (void)didReceiveMessageNotification:(NSNotification *)notification {
    __weak typeof(self) blockSelf_ = self;
    //处理好友请求
    RCMessage *message = notification.object;
    if ([message.content isMemberOfClass:[RCDContactNotificationMessage class]] || [message.content isMemberOfClass:[RCContactNotificationMessage class]]) {
        if (message.conversationType != ConversationType_SYSTEM) {
            NSLog(@"好友消息要发系统消息！！！");
#if DEBUG
            @throw [[NSException alloc] initWithName:@"error" reason:@"好友消息要发系统消息！！！" userInfo:nil];
#endif
        }
        NSString *sourceUserId;
        if ([message.content isMemberOfClass:[RCDContactNotificationMessage class]]) {
            RCDContactNotificationMessage *_contactNotificationMsg = (RCDContactNotificationMessage*)message.content;
            sourceUserId = _contactNotificationMsg.sourceUserId;
        }else if([message.content isMemberOfClass:[RCContactNotificationMessage class]]){
            RCContactNotificationMessage *_contactNotificationMsg = (RCContactNotificationMessage*)message.content;
            sourceUserId = _contactNotificationMsg.sourceUserId;
        }

        if (sourceUserId == nil || sourceUserId.length == 0) {
            return;
        }
        //该接口需要替换为从消息体获取好友请求的用户信息
        [RCDUserInfoManager getUserInfoFromServer:sourceUserId
                                         complete:^(RCUserInfo *user) {
                                             RCDFriendInfo *rcduserinfo_ = [RCDFriendInfo new];
                                             rcduserinfo_.name = user.name;
                                             rcduserinfo_.userId = user.userId;
                                             rcduserinfo_.portraitUri = user.portraitUri;
                                             
                                             RCConversationModel *customModel = [RCConversationModel new];
                                             customModel.conversationModelType = RC_CONVERSATION_MODEL_TYPE_CUSTOMIZATION;
                                             customModel.extend = rcduserinfo_;
                                             customModel.conversationType = message.conversationType;
                                             customModel.targetId = message.targetId;
                                             customModel.sentTime = message.sentTime;
                                             customModel.receivedTime = message.receivedTime;
                                             customModel.senderUserId = message.senderUserId;
                                             customModel.lastestMessage = message.content;
                                             //[_myDataSource insertObject:customModel atIndex:0];
                                             
                                             // local cache for userInfo
                                             NSDictionary *userinfoDic =
                                             @{@"username" : rcduserinfo_.name, @"portraitUri" : rcduserinfo_.portraitUri};
                                             [DEFAULTS setObject:userinfoDic
                                              forKey:sourceUserId];
                                             [DEFAULTS synchronize];
                                             
                                             dispatch_async(dispatch_get_main_queue(), ^{
                                                 //调用父类刷新未读消息数
                                                 [blockSelf_ refreshConversationTableViewWithConversationModel:customModel];
                                                 [blockSelf_ notifyUpdateUnreadMessageCount];
                                                 
                                                 //当消息为RCDContactNotificationMessage时，没有调用super，如果是最后一条消息，可能需要刷新一下整个列表。
                                                 //原因请查看super didReceiveMessageNotification的注释。
                                                 NSNumber *left = [notification.userInfo objectForKey:@"left"];
                                                 if (0 == left.integerValue) {
                                                     [super refreshConversationTableViewIfNeeded];
                                                 }
                                             });
                                         }];
    } else if([message.content isKindOfClass:[RCDGroupNotificationMessage class]]){
        RCDGroupNotificationMessage *groupNotif = (RCDGroupNotificationMessage *)message.content;
        if (![groupNotif.operation isEqualToString:RCDGroupMemberManagerRemove]) {
            [super didReceiveMessageNotification:notification];
        }
    } else {
        //调用父类刷新未读消息数
        [super didReceiveMessageNotification:notification];
    }
}

#pragma mark - target action
/**
 *  弹出层
 *
 *  @param sender sender description
 */
- (void)showMenu{
    NSArray *menuItems = @[
        [KxMenuItem menuItem:RCDLocalizedString(@"start_chatting")
                       image:[UIImage imageNamed:@"startchat_icon"]
                      target:self
                      action:@selector(pushChat:)],

        [KxMenuItem menuItem:RCDLocalizedString(@"create_groups")
                       image:[UIImage imageNamed:@"creategroup_icon"]
                      target:self
                      action:@selector(pushContactSelected:)],

        [KxMenuItem menuItem:RCDLocalizedString(@"add_contacts")
                       image:[UIImage imageNamed:@"addfriend_icon"]
                      target:self
                      action:@selector(pushAddFriend:)]
    ];

    UIBarButtonItem *rightBarButton = self.tabBarController.navigationItem.rightBarButtonItems[0];
    CGRect targetFrame = [self.navigationController.view convertRect:rightBarButton.customView.frame fromView:rightBarButton.customView.superview];
    targetFrame.origin.y = targetFrame.origin.y - 15 - 8.5;
    [KxMenu setTintColor:HEXCOLOR(0x000000)];
    [KxMenu setTitleFont:[UIFont systemFontOfSize:17]];
    [KxMenu showMenuInView:self.tabBarController.navigationController.navigationBar.superview
                  fromRect:targetFrame
                 menuItems:menuItems];
}

- (void)gotoNextConversation {
    NSUInteger i;
    //设置contentInset是为了滚动到底部的时候，避免conversationListTableView自动回滚。
    self.conversationListTableView.contentInset =
    UIEdgeInsetsMake(0, 0, self.conversationListTableView.frame.size.height, 0);
    for (i = self.index + 1; i < self.conversationListDataSource.count; i++) {
        RCConversationModel *model = self.conversationListDataSource[i];
        if (model.unreadMessageCount > 0) {
            NSIndexPath *scrollIndexPath = [NSIndexPath indexPathForRow:i inSection:0];
            self.index = i;
            [self.conversationListTableView scrollToRowAtIndexPath:scrollIndexPath
                                                  atScrollPosition:UITableViewScrollPositionTop
                                                          animated:YES];
            break;
        }
    }
    //滚动到起始位置
    if (i >= self.conversationListDataSource.count) {
        //    self.conversationListTableView.contentInset = UIEdgeInsetsMake(0, 0, 0, 0);
        for (i = 0; i < self.conversationListDataSource.count; i++) {
            RCConversationModel *model = self.conversationListDataSource[i];
            if (model.unreadMessageCount > 0) {
                NSIndexPath *scrollIndexPath = [NSIndexPath indexPathForRow:i inSection:0];
                self.index = i;
                [self.conversationListTableView scrollToRowAtIndexPath:scrollIndexPath
                                                      atScrollPosition:UITableViewScrollPositionTop
                                                              animated:YES];
                break;
            }
        }
    }
}

- (void)updateForSharedMessageInsertSuccess {
    [self refreshConversationTableViewIfNeeded];
}

- (void)refreshCell:(NSNotification *)notify {
    /*
     NSString *row = [notify object];
     RCConversationModel *model = [self.conversationListDataSource objectAtIndex:[row intValue]];
     model.unreadMessageCount = 0;
     NSIndexPath *indexPath=[NSIndexPath indexPathForRow:[row integerValue] inSection:0];
     dispatch_async(dispatch_get_main_queue(), ^{
     [self.conversationListTableView reloadRowsAtIndexPaths:[NSArray arrayWithObjects:indexPath,nil]
     withRowAnimation:UITableViewRowAnimationNone];
     });
     */
    [self refreshConversationTableViewIfNeeded];
}

#pragma mark - helper
- (void)registerNotification{
    //接收定位到未读数会话的通知
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(gotoNextConversation)
                                                 name:@"GotoNextConversation"
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(updateForSharedMessageInsertSuccess)
                                                 name:@"RCDSharedMessageInsertSuccess"
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(refreshCell:)
                                                 name:@"RefreshConversationList"
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(updateBadgeValueForTabBarItem)
                                                 name:RCKitDispatchRecallMessageNotification
                                               object:nil];
    
}

- (void)updateBadgeValueForTabBarItem {
    __weak typeof(self) __weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        int count = [[RCIMClient sharedRCIMClient] getUnreadCount:__weakSelf.displayConversationTypeArray];
        if (count > 0) {
            [__weakSelf.tabBarController.tabBar showBadgeOnItemIndex:0 badgeValue:count];
            
        } else {
            [__weakSelf.tabBarController.tabBar hideBadgeOnItemIndex:0];
        }
        
    });
}

/**
 *  发起聊天
 *
 *  @param sender sender description
 */
- (void)pushChat:(id)sender {
    RCDContactSelectedTableViewController *contactSelectedVC = [[RCDContactSelectedTableViewController alloc] initWithTitle:RCDLocalizedString(@"start_chatting") isAllowsMultipleSelection:NO];
    [self.navigationController pushViewController:contactSelectedVC animated:YES];
}

- (void)pushChatVC:(RCConversationModel *)model{
    RCDChatViewController *chatVC = [[RCDChatViewController alloc] init];
    chatVC.conversationType = model.conversationType;
    chatVC.targetId = model.targetId;
    chatVC.userName = model.conversationTitle;
    chatVC.title = model.conversationTitle;
    if (model.conversationModelType == RC_CONVERSATION_MODEL_TYPE_NORMAL) {
        chatVC.unReadMessage = model.unreadMessageCount;
        chatVC.enableNewComingMessageIcon = YES; //开启消息提醒
        chatVC.enableUnreadMessageIcon = YES;
        if (model.conversationType == ConversationType_SYSTEM) {
            chatVC.userName = RCDLocalizedString(@"de_actionbar_sub_system");
            chatVC.title = RCDLocalizedString(@"de_actionbar_sub_system");
        }else if (model.conversationType == ConversationType_PRIVATE) {
            chatVC.displayUserNameInCell = NO;
        }
    }
    [self.navigationController pushViewController:chatVC animated:YES];
}

/**
 *  创建群组
 *
 *  @param sender sender description
 */
- (void)pushContactSelected:(id)sender {
    RCDContactSelectedTableViewController *contactSelectedVC = [[RCDContactSelectedTableViewController alloc] initWithTitle:RCDLocalizedString(@"select_contact") isAllowsMultipleSelection:YES];
    contactSelectedVC.groupOptionType = RCDContactSelectedGroupOptionTypeCreate;
    [self.navigationController pushViewController:contactSelectedVC animated:YES];
}

/**
 *  添加好友
 *
 *  @param sender sender description
 */
- (void)pushAddFriend:(id)sender {
    RCDSearchFriendController *searchFirendVC = [[RCDSearchFriendController alloc] init];
    [self.navigationController pushViewController:searchFirendVC animated:YES];
}

- (void)pushAddressBook{
    RCDAddressBookViewController *addressBookVC = [[RCDAddressBookViewController alloc] init];
    [self.navigationController pushViewController:addressBookVC animated:YES];
}

- (void)checkVersion {
    __weak typeof(self) __weakSelf = self;
    [RCDLoginManager getVersionInfo:^(BOOL needUpdate, NSString * _Nonnull finalURL) {
        if (needUpdate) {
            rcd_dispatch_main_async_safe(^{
                [DEFAULTS setObject:finalURL forKey:RCDApplistURLKey];
                [DEFAULTS setObject:@(needUpdate) forKey:RCDNeedUpdateKey];
                [DEFAULTS synchronize];
                [__weakSelf.tabBarController.tabBar showBadgeOnItemIndex:3];
            });
        }
    }];
}

- (void)setTabBarStyle{
    //修改tabbar的背景色
    UIView *tabBarBG = [UIView new];
    tabBarBG.backgroundColor = HEXCOLOR(0xf9f9f9);
    tabBarBG.frame = self.tabBarController.tabBar.bounds;
    [[UITabBar appearance] insertSubview:tabBarBG atIndex:0];
    [[UITabBarItem appearance]
     setTitleTextAttributes:[NSDictionary
                             dictionaryWithObjectsAndKeys:HEXCOLOR(0x999999), UITextAttributeTextColor, nil]
     forState:UIControlStateNormal];
    
    [[UITabBarItem appearance]
     setTitleTextAttributes:[NSDictionary
                             dictionaryWithObjectsAndKeys:HEXCOLOR(0x0099ff), UITextAttributeTextColor, nil]
     forState:UIControlStateSelected];
}

- (void)initSubviews{
    self.edgesForExtendedLayout = UIRectEdgeNone;
    self.navigationController.navigationBar.translucent = NO;
    //设置tableView样式
    self.conversationListTableView.separatorColor = [UIColor colorWithHexString:@"dfdfdf" alpha:1.0f];
    self.conversationListTableView.tableFooterView = [UIView new];
    [self.headerView addSubview:self.searchBar];
    self.conversationListTableView.tableHeaderView = self.headerView;
    // 设置在NavigatorBar中显示连接中的提示
    self.showConnectingStatusOnNavigatorBar = YES;
    //定位未读数会话
    self.index = 0;
}

- (void)setNaviItem{
    RCDUIBarButtonItem *rightBtn = [[RCDUIBarButtonItem alloc] initContainImage:[UIImage imageNamed:@"add"]
                                                                 imageViewFrame:CGRectMake(8.5, 8.5, 17, 17)
                                                                    buttonTitle:nil
                                                                     titleColor:nil
                                                                     titleFrame:CGRectZero
                                                                    buttonFrame:CGRectMake(0, 0, 34, 34)
                                                                         target:self
                                                                         action:@selector(showMenu)];
    self.tabBarController.navigationItem.rightBarButtonItems = @[rightBtn];
    self.tabBarController.navigationItem.title = RCDLocalizedString(@"conversation");
}

#pragma mark - geter & setter
- (RCDSearchBar *)searchBar {
    if (!_searchBar) {
        _searchBar =
        [[RCDSearchBar alloc] initWithFrame:CGRectMake(0, 0, self.conversationListTableView.frame.size.width, 44)];
        _searchBar.delegate = self;
    }
    return _searchBar;
}

- (UIView *)headerView {
    if (!_headerView) {
        _headerView =
        [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.conversationListTableView.frame.size.width, 44)];
    }
    return _headerView;
}
@end
