import Image from "next/image";
import Link from "next/link";
import type { SiteLanguage } from "@/lib/language";

type LandingPageProps = {
  lang: SiteLanguage;
};

export function LandingPage({ lang }: LandingPageProps) {
  const isJapanese = lang === "ja";
  const copy = isJapanese
    ? {
        navFeatures: "できること",
        navFlow: "使い方",
        support: "サポート",
        sectionKicker: "YOUR DAILY LISTENING RITUAL",
        sectionTitle: "ニュースを探す時間も、\n読む時間も、ひとつに。",
        sectionBody: "StackCastは、ニュースとの出会いから保存、音声化、再生までをひと続きの体験にします。忙しい日にも、情報を諦めないための新しい習慣です。",
        personalTitle: "あなたの興味から、今日の5件を。",
        personalBody: "興味ジャンルやおすすめメモリをもとに、今知りたいニュースを毎日セレクト。興味のない話題も反映しながら、少しずつあなたらしいフィードに育ちます。",
        saveTitle: "気になった記事を、あとでの自分へ。",
        saveBody: "Web記事を共有メニューやURLからすばやく保存。読み終えた記事も、期限が近い記事も、ひとつのStockで迷わず整理できます。",
        castTitle: "選んだ記事が、ひとつの音声Castに。",
        castBody: "保存した記事を選ぶと、AIが要点をまとめて聴きやすい音声へ。長さや再生速度を選び、移動や家事の時間に合わせて楽しめます。",
        flowKicker: "FROM SCREEN TO SOUND",
        flowTitle: "3つのステップで、\n読むを聴くに変える。",
        steps: [
          ["01", "見つける", "興味に合うニュースをチェック。Webで見つけた記事も保存できます。"],
          ["02", "まとめる", "気になる記事を選び、聴きたい時間に合わせてCastを作成します。"],
          ["03", "聴く", "生成中はアプリを閉じても大丈夫。完成したCastを好きな場所で再生。"],
        ],
        listeningTitle: "画面を閉じても、\n知りたい気持ちは続いていく。",
        listeningBody: "通勤、散歩、家事、休憩。これまでニュースを読めなかった時間が、世界に追いつく時間へ変わります。",
        privacyNote: "AI処理は、内容を確認し同意したときだけ開始します。",
        closingKicker: "STACK YOUR CURIOSITY",
        closingTitle: "あとで読むを、\n今日から聴こう。",
        closingBody: "StackCastは、あなたの好奇心を無理なく日常へ運ぶためのニュースアプリです。",
        comingSoon: "まもなくApp Storeで公開",
        footerTagline: "知りたいことを、耳で楽しむ。",
        terms: "利用規約",
        privacy: "プライバシーポリシー",
      }
    : {
        navFeatures: "Features",
        navFlow: "How it works",
        support: "Support",
        sectionKicker: "YOUR DAILY LISTENING RITUAL",
        sectionTitle: "Find the news. Save it.\nListen when you are ready.",
        sectionBody: "StackCast connects discovery, saving, audio generation, and playback in one calm experience—a new way to stay informed on busy days.",
        personalTitle: "Five stories, selected around you.",
        personalBody: "Your interests and recommendation memory shape a fresh daily selection. Hide what does not resonate and the feed grows more personal over time.",
        saveTitle: "Save what matters for later.",
        saveBody: "Keep articles from the share sheet or a URL. Organize unread, expiring, and completed stories in one focused Stock.",
        castTitle: "Turn selected stories into one Cast.",
        castBody: "AI distills your saved articles into audio made for listening. Choose a duration and playback speed that fits the moment.",
        flowKicker: "FROM SCREEN TO SOUND",
        flowTitle: "Three simple steps from\nreading to listening.",
        steps: [
          ["01", "Discover", "Browse news selected for your interests, or save an article you find on the web."],
          ["02", "Create", "Choose the stories that matter and create a Cast that fits the time you have."],
          ["03", "Listen", "Leave the app while it is generated, then play the finished Cast wherever you are."],
        ],
        listeningTitle: "Close the screen.\nKeep your curiosity moving.",
        listeningBody: "Commutes, walks, chores, and breaks become time to catch up with the world—without staying glued to a screen.",
        privacyNote: "AI processing begins only after you review the details and consent.",
        closingKicker: "STACK YOUR CURIOSITY",
        closingTitle: "Turn read later\ninto listen today.",
        closingBody: "StackCast brings your curiosity into everyday life with a calmer way to follow the news.",
        comingSoon: "Coming soon to the App Store",
        footerTagline: "Enjoy what matters, by ear.",
        terms: "Terms of Service",
        privacy: "Privacy Policy",
      };

  return (
    <main className="landing">
      <header className="site-header">
        <Link href={`/${lang}`} className="brand" aria-label="StackCast home">
          <Image src="/marketing/app-icon.png" width={42} height={42} alt="" className="brand-icon" priority />
          <span>StackCast</span>
        </Link>
        <nav className="site-nav" aria-label={isJapanese ? "メインナビゲーション" : "Main navigation"}>
          <a href="#features">{copy.navFeatures}</a>
          <a href="#how-it-works">{copy.navFlow}</a>
          <Link href={`/${lang}/support`}>{copy.support}</Link>
          <Link href={`/${isJapanese ? "en" : "ja"}`} className="language-link">
            {isJapanese ? "EN" : "日本語"}
          </Link>
        </nav>
      </header>

      <section className="hero">
        <div className="hero-copy">
          <div className="product-label">
            <Image src="/marketing/app-icon.png" width={30} height={30} alt="" />
            <span>{isJapanese ? "AIニュース音声アプリ" : "AI news audio app"}</span>
          </div>
          <p className="eyebrow">DISCOVER · SAVE · LISTEN</p>
          <h1>{isJapanese ? "ニュースを、あなた専用の音声番組に。" : "Turn the news into your personal audio show."}</h1>
          <p className="hero-description">
            {isJapanese
              ? "StackCastは、あなた向けのニュースを見つけ、気になる記事を保存し、AIが要約した音声Castとして聴けるアプリです。通勤中や家事の途中など、画面を見られない時間にもニュースを楽しめます。"
              : "StackCast helps you discover news selected for you, save the stories that matter, and listen to them as AI-generated audio Casts—perfect for commutes, chores, and time away from the screen."}
          </p>
          <div className="hero-explainer" aria-label={isJapanese ? "StackCastの3つの機能" : "Three things StackCast does"}>
            <div>
              <span className="explainer-icon" aria-hidden="true">01</span>
              <strong>{isJapanese ? "見つける" : "Discover"}</strong>
              <small>{isJapanese ? "興味に合うニュース" : "News for your interests"}</small>
            </div>
            <span className="explainer-arrow" aria-hidden="true">→</span>
            <div>
              <span className="explainer-icon" aria-hidden="true">02</span>
              <strong>{isJapanese ? "保存する" : "Save"}</strong>
              <small>{isJapanese ? "あとで読みたい記事" : "Stories for later"}</small>
            </div>
            <span className="explainer-arrow" aria-hidden="true">→</span>
            <div>
              <span className="explainer-icon" aria-hidden="true">03</span>
              <strong>{isJapanese ? "耳で聴く" : "Listen"}</strong>
              <small>{isJapanese ? "AI要約の音声Cast" : "AI-generated Casts"}</small>
            </div>
          </div>
          <div className="hero-actions">
            <span className="availability-pill">
              <span className="availability-dot" />
              {isJapanese ? "まもなくApp Storeで公開" : "Coming soon to the App Store"}
            </span>
            <a href="#features" className="text-link">
              {isJapanese ? "アプリの仕組みを見る" : "See how it works"} <span aria-hidden="true">↓</span>
            </a>
          </div>
        </div>

        <div className="hero-visual" aria-label={isJapanese ? "StackCastのアプリ画面" : "StackCast app screens"}>
          <div className="ambient-orb ambient-orb-one" />
          <div className="ambient-orb ambient-orb-two" />
          <div className="phone phone-back" aria-hidden="true">
            <Image src="/marketing/personal-news.png" width={1320} height={2868} alt="" sizes="240px" />
          </div>
          <div className="phone phone-front">
            <Image
              src="/marketing/home.png"
              width={1320}
              height={2868}
              alt={isJapanese ? "StackCastのホーム画面" : "StackCast home screen"}
              sizes="(max-width: 700px) 62vw, 320px"
              priority
            />
          </div>
          <div className="hero-player-card" aria-hidden="true">
            <Image src="/marketing/app-icon.png" width={46} height={46} alt="" />
            <div className="hero-player-copy">
              <span>{isJapanese ? "再生中" : "Now playing"}</span>
              <strong>{isJapanese ? "今日のニュースCast" : "Today’s News Cast"}</strong>
            </div>
            <div className="waveform">
              <i /><i /><i /><i /><i /><i /><i />
            </div>
            <span className="hero-play">▶</span>
          </div>
        </div>
      </section>

      <section id="features" className="story-intro section-shell">
        <div className="section-heading">
          <p className="section-kicker">{copy.sectionKicker}</p>
          <h2>{copy.sectionTitle}</h2>
        </div>
        <p className="section-lede">{copy.sectionBody}</p>
      </section>

      <section className="feature-grid section-shell" aria-label={copy.navFeatures}>
        <article className="feature-card feature-card-large">
          <div className="feature-copy">
            <span className="feature-number">01</span>
            <h3>{copy.personalTitle}</h3>
            <p>{copy.personalBody}</p>
          </div>
          <div className="feature-media feature-media-news">
            <div className="feature-phone feature-phone-news">
              <Image src="/marketing/personal-news.png" width={1320} height={2868} alt={copy.personalTitle} sizes="(max-width: 800px) 72vw, 360px" />
            </div>
            <Image src="/marketing/discover.png" width={1254} height={1254} alt="" className="feature-illustration" sizes="260px" />
          </div>
        </article>

        <article className="feature-card feature-card-stock">
          <div className="feature-copy">
            <span className="feature-number">02</span>
            <h3>{copy.saveTitle}</h3>
            <p>{copy.saveBody}</p>
          </div>
          <div className="feature-media feature-media-stock">
            <div className="feature-phone feature-phone-stock">
              <Image src="/marketing/stock.png" width={1320} height={2868} alt={copy.saveTitle} sizes="(max-width: 800px) 72vw, 330px" />
            </div>
          </div>
        </article>

        <article className="feature-card feature-card-cast">
          <div className="feature-copy">
            <span className="feature-number">03</span>
            <h3>{copy.castTitle}</h3>
            <p>{copy.castBody}</p>
          </div>
          <div className="feature-media feature-media-cast">
            <Image src="/marketing/cast-audio.png" width={1254} height={1254} alt="" className="cast-illustration" sizes="(max-width: 800px) 70vw, 410px" />
          </div>
        </article>
      </section>

      <section id="how-it-works" className="flow-section">
        <div className="section-shell">
          <p className="section-kicker light">{copy.flowKicker}</p>
          <h2>{copy.flowTitle}</h2>
          <div className="steps-grid">
            {copy.steps.map(([number, title, description]) => (
              <article className="step" key={number}>
                <span>{number}</span>
                <h3>{title}</h3>
                <p>{description}</p>
              </article>
            ))}
          </div>
        </div>
      </section>

      <section className="listening-section section-shell">
        <div className="listening-visual">
          <div className="listening-halo" />
          <Image src="/marketing/listen.png" width={1254} height={1254} alt="" className="listening-illustration" sizes="(max-width: 800px) 82vw, 540px" />
          <div className="mini-player">
            <div className="mini-player-art">
              <Image src="/marketing/app-icon.png" width={52} height={52} alt="" />
            </div>
            <div className="mini-player-copy">
              <strong>StackCast Daily</strong>
              <span>{isJapanese ? "今日知っておきたい5つの話題" : "Five stories to know today"}</span>
            </div>
            <span className="play-button" aria-hidden="true">▶</span>
          </div>
        </div>
        <div className="listening-copy">
          <p className="section-kicker">LISTEN ANYWHERE</p>
          <h2>{copy.listeningTitle}</h2>
          <p>{copy.listeningBody}</p>
          <div className="privacy-note">
            <span aria-hidden="true">✓</span>
            {copy.privacyNote}
          </div>
        </div>
      </section>

      <section className="closing-section section-shell">
        <div className="closing-copy">
          <p className="section-kicker light">{copy.closingKicker}</p>
          <h2>{copy.closingTitle}</h2>
          <p>{copy.closingBody}</p>
          <span className="closing-pill">
            <span className="availability-dot" />
            {copy.comingSoon}
          </span>
        </div>
        <div className="closing-media">
          <Image src="/marketing/app-icon.png" width={1024} height={1024} alt="StackCast" className="closing-icon" sizes="(max-width: 800px) 62vw, 400px" />
        </div>
      </section>

      <footer className="site-footer section-shell">
        <div className="footer-brand">
          <Image src="/marketing/app-icon.png" width={44} height={44} alt="" />
          <div>
            <strong>StackCast</strong>
            <span>{copy.footerTagline}</span>
          </div>
        </div>
        <nav aria-label={isJapanese ? "フッターナビゲーション" : "Footer navigation"}>
          <Link href={`/${lang}/terms`}>{copy.terms}</Link>
          <Link href={`/${lang}/privacy`}>{copy.privacy}</Link>
          <Link href={`/${lang}/support`}>{copy.support}</Link>
        </nav>
        <p>© 2026 NEXRO</p>
      </footer>
    </main>
  );
}
