//
//  WQMProjectLinks.h
//  WQManager
//
//  项目自身的 GitHub 地址集中在这里，换账号/组织时只改这一处。
//

#ifndef WQMProjectLinks_h
#define WQMProjectLinks_h

#define WQM_REPOSITORY_OWNER @"hseons"
#define WQM_REPOSITORY_NAME @"WQManager"
#define WQM_REPOSITORY_SLUG WQM_REPOSITORY_OWNER @"/" WQM_REPOSITORY_NAME
#define WQM_REPOSITORY_URL @"https://github.com/" WQM_REPOSITORY_SLUG
#define WQM_REPOSITORY_RELEASES_URL WQM_REPOSITORY_URL @"/releases"
#define WQM_REPOSITORY_LATEST_RELEASE_API @"https://api.github.com/repos/" WQM_REPOSITORY_SLUG @"/releases/latest"

#endif
