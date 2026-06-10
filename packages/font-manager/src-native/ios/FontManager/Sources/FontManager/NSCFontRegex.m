#import "NSCFontRegex.h"

NSString *const NSCFontFacePattern = @"@font-face\\s*\\{([\\s\\S]*?)\\}";
NSString *const NSCPropertyPattern =
    @"([a-zA-Z-]+)\\s*:\\s*([^;]+);";