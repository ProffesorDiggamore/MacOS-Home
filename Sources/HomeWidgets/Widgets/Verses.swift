import Foundation

struct Verse {
    let reference: String
    let text: String
}

/// Verses from the King James Version (public domain).
enum Verses {
    static let all: [Verse] = [
        Verse(reference: "John 3:16", text: "For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish, but have everlasting life."),
        Verse(reference: "Philippians 4:13", text: "I can do all things through Christ which strengtheneth me."),
        Verse(reference: "Jeremiah 29:11", text: "For I know the thoughts that I think toward you, saith the LORD, thoughts of peace, and not of evil, to give you an expected end."),
        Verse(reference: "Proverbs 3:5–6", text: "Trust in the LORD with all thine heart; and lean not unto thine own understanding. In all thy ways acknowledge him, and he shall direct thy paths."),
        Verse(reference: "Romans 8:28", text: "And we know that all things work together for good to them that love God, to them who are the called according to his purpose."),
        Verse(reference: "Psalm 23:1", text: "The LORD is my shepherd; I shall not want."),
        Verse(reference: "Isaiah 40:31", text: "But they that wait upon the LORD shall renew their strength; they shall mount up with wings as eagles; they shall run, and not be weary; and they shall walk, and not faint."),
        Verse(reference: "Joshua 1:9", text: "Have not I commanded thee? Be strong and of a good courage; be not afraid, neither be thou dismayed: for the LORD thy God is with thee whithersoever thou goest."),
        Verse(reference: "Matthew 11:28", text: "Come unto me, all ye that labour and are heavy laden, and I will give you rest."),
        Verse(reference: "Psalm 46:10", text: "Be still, and know that I am God: I will be exalted among the heathen, I will be exalted in the earth."),
        Verse(reference: "2 Timothy 1:7", text: "For God hath not given us the spirit of fear; but of power, and of love, and of a sound mind."),
        Verse(reference: "Romans 12:2", text: "And be not conformed to this world: but be ye transformed by the renewing of your mind, that ye may prove what is that good, and acceptable, and perfect, will of God."),
        Verse(reference: "Galatians 5:22–23", text: "But the fruit of the Spirit is love, joy, peace, longsuffering, gentleness, goodness, faith, Meekness, temperance: against such there is no law."),
        Verse(reference: "Psalm 119:105", text: "Thy word is a lamp unto my feet, and a light unto my path."),
        Verse(reference: "Matthew 6:33", text: "But seek ye first the kingdom of God, and his righteousness; and all these things shall be added unto you."),
        Verse(reference: "Philippians 4:6–7", text: "Be careful for nothing; but in every thing by prayer and supplication with thanksgiving let your requests be made known unto God. And the peace of God, which passeth all understanding, shall keep your hearts and minds through Christ Jesus."),
        Verse(reference: "Isaiah 41:10", text: "Fear thou not; for I am with thee: be not dismayed; for I am thy God: I will strengthen thee; yea, I will help thee; yea, I will uphold thee with the right hand of my righteousness."),
        Verse(reference: "Psalm 118:24", text: "This is the day which the LORD hath made; we will rejoice and be glad in it."),
        Verse(reference: "Lamentations 3:22–23", text: "It is of the LORD's mercies that we are not consumed, because his compassions fail not. They are new every morning: great is thy faithfulness."),
        Verse(reference: "Romans 15:13", text: "Now the God of hope fill you with all joy and peace in believing, that ye may abound in hope, through the power of the Holy Ghost."),
        Verse(reference: "Hebrews 11:1", text: "Now faith is the substance of things hoped for, the evidence of things not seen."),
        Verse(reference: "1 Peter 5:7", text: "Casting all your care upon him; for he careth for you."),
        Verse(reference: "Psalm 27:1", text: "The LORD is my light and my salvation; whom shall I fear? the LORD is the strength of my life; of whom shall I be afraid?"),
        Verse(reference: "John 14:6", text: "Jesus saith unto him, I am the way, the truth, and the life: no man cometh unto the Father, but by me."),
        Verse(reference: "Ephesians 2:8–9", text: "For by grace are ye saved through faith; and that not of yourselves: it is the gift of God: Not of works, lest any man should boast."),
        Verse(reference: "Micah 6:8", text: "He hath shewed thee, O man, what is good; and what doth the LORD require of thee, but to do justly, and to love mercy, and to walk humbly with thy God?"),
        Verse(reference: "1 Timothy 4:12", text: "Let no man despise thy youth; but be thou an example of the believers, in word, in conversation, in charity, in spirit, in faith, in purity."),
        Verse(reference: "Psalm 37:4", text: "Delight thyself also in the LORD; and he shall give thee the desires of thine heart."),
        Verse(reference: "Matthew 5:16", text: "Let your light so shine before men, that they may see your good works, and glorify your Father which is in heaven."),
        Verse(reference: "Romans 5:8", text: "But God commendeth his love toward us, in that, while we were yet sinners, Christ died for us."),
        Verse(reference: "2 Corinthians 5:17", text: "Therefore if any man be in Christ, he is a new creature: old things are passed away; behold, all things are become new."),
        Verse(reference: "James 1:5", text: "If any of you lack wisdom, let him ask of God, that giveth to all men liberally, and upbraideth not; and it shall be given him."),
        Verse(reference: "Psalm 121:1–2", text: "I will lift up mine eyes unto the hills, from whence cometh my help. My help cometh from the LORD, which made heaven and earth."),
        Verse(reference: "Proverbs 18:10", text: "The name of the LORD is a strong tower: the righteous runneth into it, and is safe."),
        Verse(reference: "Nahum 1:7", text: "The LORD is good, a strong hold in the day of trouble; and he knoweth them that trust in him."),
        Verse(reference: "John 16:33", text: "These things I have spoken unto you, that in me ye might have peace. In the world ye shall have tribulation: but be of good cheer; I have overcome the world."),
        Verse(reference: "Psalm 34:8", text: "O taste and see that the LORD is good: blessed is the man that trusteth in him."),
        Verse(reference: "Zephaniah 3:17", text: "The LORD thy God in the midst of thee is mighty; he will save, he will rejoice over thee with joy; he will rest in his love, he will joy over thee with singing."),
        Verse(reference: "Deuteronomy 31:6", text: "Be strong and of a good courage, fear not, nor be afraid of them: for the LORD thy God, he it is that doth go with thee; he will not fail thee, nor forsake thee."),
        Verse(reference: "1 John 4:19", text: "We love him, because he first loved us."),
        Verse(reference: "Psalm 139:14", text: "I will praise thee; for I am fearfully and wonderfully made: marvellous are thy works; and that my soul knoweth right well."),
        Verse(reference: "Isaiah 26:3", text: "Thou wilt keep him in perfect peace, whose mind is stayed on thee: because he trusteth in thee."),
        Verse(reference: "Hebrews 13:8", text: "Jesus Christ the same yesterday, and to day, and for ever."),
        Verse(reference: "Romans 10:9", text: "That if thou shalt confess with thy mouth the Lord Jesus, and shalt believe in thine heart that God hath raised him from the dead, thou shalt be saved."),
        Verse(reference: "Psalm 19:1", text: "The heavens declare the glory of God; and the firmament sheweth his handywork."),
        Verse(reference: "Mark 10:27", text: "And Jesus looking upon them saith, With men it is impossible, but not with God: for with God all things are possible."),
        Verse(reference: "Proverbs 16:3", text: "Commit thy works unto the LORD, and thy thoughts shall be established."),
        Verse(reference: "Psalm 56:3", text: "What time I am afraid, I will trust in thee."),
        Verse(reference: "Exodus 14:14", text: "The LORD shall fight for you, and ye shall hold your peace."),
        Verse(reference: "Galatians 6:9", text: "And let us not be weary in well doing: for in due season we shall reap, if we faint not."),
        Verse(reference: "John 8:12", text: "Then spake Jesus again unto them, saying, I am the light of the world: he that followeth me shall not walk in darkness, but shall have the light of life."),
        Verse(reference: "Psalm 100:4", text: "Enter into his gates with thanksgiving, and into his courts with praise: be thankful unto him, and bless his name."),
        Verse(reference: "1 Thessalonians 5:16–18", text: "Rejoice evermore. Pray without ceasing. In every thing give thanks: for this is the will of God in Christ Jesus concerning you."),
        Verse(reference: "Matthew 22:37", text: "Jesus said unto him, Thou shalt love the Lord thy God with all thy heart, and with all thy soul, and with all thy mind."),
        Verse(reference: "John 1:5", text: "And the light shineth in darkness; and the darkness comprehended it not."),
    ]

    /// Verses short enough to read comfortably in a small widget.
    static let short: [Verse] = all.filter { $0.text.count <= 110 }
}
