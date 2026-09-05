'use client';
import { useEffect, useRef, useState } from 'react';
import Image from 'next/image';
import {
  Check,
  RotateCcw,
  ChevronRight,
  ArrowLeft,
  EyeOff,
  Eye,
  ArrowUpRight,
  ArrowRight,
} from 'lucide-react';
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/components/ui/tabs';
import {
  Accordion,
  AccordionItem,
  AccordionTrigger,
  AccordionContent,
} from '@/components/ui/accordion';
const questions = [
  {
    q: 'What is Previously.?',
    a: 'A TV and anime tracker for iPhone, with episode progress, seasons, release updates and spoiler controls.',
  },
  {
    q: 'Can I watch shows here?',
    a: 'Previously. tracks your progress. Watch through your usual streaming services.',
  },
  {
    q: 'Can I export my library?',
    a: 'Yes. Export your shows and progress as JSON or CSV from Profile.',
  },
  {
    q: 'When can I get it?',
    a: 'An iPhone release is coming. The App Store link will appear here when it’s available.',
  },
];

const shows = [
  {
    id: 'severance',
    title: 'Severance',
    kind: 'TV SERIES',
    season: 2,
    episodes: 10,
    progress: 3,
    poster: 'severance-poster.jpg',
    artwork: 'severance.jpg',
    artAlt: 'The Severance cast in a Lumon corridor',
  },
  {
    id: 'bear',
    title: 'The Bear',
    kind: 'TV SERIES',
    season: 2,
    episodes: 10,
    progress: 2,
    poster: 'bear.jpg',
    artwork: 'bear-wide.jpg',
    artAlt: 'The Bear cast gathered around a restaurant table',
  },
  {
    id: 'frieren',
    title: 'Frieren',
    kind: 'ANIME',
    season: 1,
    episodes: 28,
    progress: 0,
    poster: 'frieren-poster.jpg',
    artwork: 'frieren-wide.jpg',
    artAlt: 'Frieren, Fern and Stark on a sunlit hillside',
  },
];

export function Experience() {
  const [view, setView] = useState('library');
  const [selected, setSelected] = useState('severance');
  const [saved, setSaved] = useState<Record<string, boolean>>({});
  const actionRef = useRef<HTMLButtonElement>(null);
  const focusOnOpen = useRef(false);
  const [focusRequest, setFocusRequest] = useState(0);
  const showIndex = Math.max(
    0,
    shows.findIndex((item) => item.id === selected),
  );
  const show = shows[showIndex];
  const watched = Boolean(saved[show.id]);
  const watchedCount = show.progress + Number(watched);
  const nextShow = shows[(showIndex + 1) % shows.length];
  const openShow = (id: string) => {
    focusOnOpen.current = true;
    setFocusRequest((request) => request + 1);
    setSelected(id);
    setUpdates(false);
    setView('today');
    document.getElementById('experience')?.scrollIntoView({
      behavior: window.matchMedia('(prefers-reduced-motion: reduce)').matches
        ? 'instant'
        : 'smooth',
      block: 'start',
    });
  };
  useEffect(() => {
    if (focusOnOpen.current && view === 'today' && actionRef.current) {
      actionRef.current.focus({ preventScroll: true });
      focusOnOpen.current = false;
    }
  }, [view, selected, focusRequest]);
  const [updates, setUpdates] = useState(false);
  const [spoilers, setSpoilers] = useState(false);
  const updatesBackRef = useRef<HTMLButtonElement>(null);
  const releaseLinkRef = useRef<HTMLButtonElement>(null);
  const updatesFocusTarget = useRef<'back' | 'release' | null>(null);
  const changeUpdates = (open: boolean) => {
    updatesFocusTarget.current = open ? 'back' : 'release';
    setUpdates(open);
  };
  useEffect(() => {
    const target = updatesFocusTarget.current;
    if (!target) return;
    const control = target === 'back' ? updatesBackRef : releaseLinkRef;
    control.current?.focus({ preventScroll: true });
    updatesFocusTarget.current = null;
  }, [updates]);
  useEffect(() => {
    const views: Record<string, string> = {
      '#experience': 'today',
      '#experience-library': 'library',
      '#experience-schedule': 'schedule',
      '#experience-updates': 'today',
    };
    const navigate = (hash: string) => {
      if (views[hash]) {
        setView(views[hash]);
        setUpdates(hash === '#experience-updates');
      }
    };
    const sync = () => navigate(window.location.hash);
    const click = (event: MouseEvent) => {
      const link =
        event.target instanceof Element ? event.target.closest('a') : null;
      if (link) navigate(link.getAttribute('href') ?? '');
    };
    sync();
    window.addEventListener('hashchange', sync);
    document.addEventListener('click', click);
    return () => {
      window.removeEventListener('hashchange', sync);
      document.removeEventListener('click', click);
    };
  }, []);
  return (
    <>
      <section className="story-hero" aria-labelledby="hero-title">
        <div className="poster-wall" aria-hidden="true">
          {[
            'severance-poster.jpg',
            'stranger-things.jpg',
            'frieren-poster.jpg',
            'succession.jpg',
            'arcane.jpg',
            'bear.jpg',
            'attack-on-titan-2x3.jpg',
            'silo.jpg',
            'the-last-of-us.jpg',
            'breaking-bad.jpg',
            'frieren-poster.jpg',
            'succession.jpg',
            'arcane.jpg',
            'severance-poster.jpg',
            'succession.jpg',
            'bear.jpg',
            'silo.jpg',
            'stranger-things.jpg',
            'attack-on-titan-2x3.jpg',
            'the-last-of-us.jpg',
            'breaking-bad.jpg',
          ].map((poster, index) => (
            <Image
              unoptimized
              key={`${poster}-${index}`}
              src={`/images/${poster}`}
              width={500}
              height={750}
              alt=""
              loading="eager"
              fetchPriority={index === 1 ? 'high' : 'auto'}
            />
          ))}
        </div>
        <div className="hero-scrim" />
        <div className="story-intro gallery-wrap">
          <span className="hero-eyebrow">YOUR TV & ANIME COMPANION</span>
          <h1 id="hero-title">
            <span>Your shows.</span>
            <span>Right where you left them.</span>
          </h1>
          <p>Track every episode. Keep every season together.</p>
          <a className="gallery-cta" href="#experience">
            Explore Previously. <ArrowRight size={20} />
          </a>
          <span className="hero-platform">Coming soon for iPhone</span>
        </div>
      </section>
      <section
        className="preview-section"
        aria-label="Explore the Previously app"
      >
        <div className="showcase gallery-wrap" id="experience">
          <span id="experience-library" className="showcase-anchor" />
          <span id="experience-schedule" className="showcase-anchor" />
          <span id="experience-updates" className="showcase-anchor" />
          <Tabs value={view} onValueChange={setView} className="showcase-tabs">
            <div className="showcase-toolbar">
              <div className="preview-heading">
                <h2>A home for every season.</h2>
                <p>Try a little of Previously.</p>
              </div>
              <TabsList
                className="showcase-navigation"
                aria-label="Explore Previously"
                data-view={view}
              >
                <TabsTrigger value="library">Collection</TabsTrigger>
                <TabsTrigger value="today">Continue</TabsTrigger>
                <TabsTrigger value="schedule">Coming next</TabsTrigger>
              </TabsList>
            </div>
            <div className="showcase-frame">
              <TabsContent value="today" className="showcase-panel">
                <div className="watch-scene" key={show.id}>
                  <div className="watch-art">
                    <Image
                      unoptimized
                      src={`/images/${show.artwork}`}
                      width={980}
                      height={552}
                      alt={show.artAlt}
                      loading="eager"
                      fetchPriority="high"
                    />
                    <span className="art-overline">
                      PICK UP WHERE YOU LEFT OFF
                    </span>
                    <div className="watch-title">
                      <span>{show.kind}</span>
                      <h2>{show.title}</h2>
                      <p>
                        Season {show.season} <span>·</span> Episode{' '}
                        {watchedCount + 1} is next
                      </p>
                    </div>
                  </div>
                  {updates ? (
                    <div className="watch-detail update-detail">
                      <button
                        className="showcase-back"
                        ref={updatesBackRef}
                        onClick={() => changeUpdates(false)}
                      >
                        <ArrowLeft size={15} /> Back to progress
                      </button>
                      <h3>Since you were away.</h3>
                      <div className="update-item">
                        <span className="update-dot" />
                        <div>
                          <strong>New episodes</strong>
                          <p>Ready when you are.</p>
                        </div>
                        <span>01</span>
                      </div>
                      <div className="update-item">
                        <span className="update-dot" />
                        <div>
                          <strong>A show is returning</strong>
                          <p>A new date to look forward to.</p>
                        </div>
                        <span>02</span>
                      </div>
                      <button
                        className="spoiler-control"
                        aria-pressed={spoilers}
                        onClick={() => setSpoilers(!spoilers)}
                      >
                        {spoilers ? <Eye size={16} /> : <EyeOff size={16} />}
                        {spoilers
                          ? 'Hide episode details'
                          : 'Reveal episode details'}
                      </button>
                      <p className="spoiler-detail">
                        {spoilers
                          ? 'Sample: An unexpected invitation.'
                          : 'Your next episode stays a surprise.'}
                      </p>
                    </div>
                  ) : (
                    <div className="watch-detail">
                      <div className="progress-heading">
                        <span>YOUR PROGRESS</span>
                        <span>
                          SEASON {String(show.season).padStart(2, '0')}
                        </span>
                      </div>
                      <div className="progress-value">
                        <strong>
                          <span className="progress-number" key={watchedCount}>
                            {String(watchedCount).padStart(2, '0')}
                          </span>
                          <span className="progress-denominator">
                            {' '}
                            / {show.episodes}
                          </span>
                        </strong>
                        <span>episodes watched</span>
                      </div>
                      <div
                        className="episode-track"
                        aria-label={`${watchedCount} of ${show.episodes} episodes watched`}
                      >
                        {Array.from({ length: show.episodes }, (_, i) => (
                          <i
                            key={i}
                            className={`${i < watchedCount ? 'complete' : ''} ${watched && i === watchedCount - 1 ? 'just-completed' : ''}`}
                          />
                        ))}
                      </div>
                      <button
                        className={`watch-action ${watched ? 'is-watched' : ''}`}
                        aria-pressed={watched}
                        ref={actionRef}
                        onClick={() =>
                          setSaved((current) => ({
                            ...current,
                            [show.id]: !current[show.id],
                          }))
                        }
                      >
                        {watched ? (
                          <RotateCcw size={17} />
                        ) : (
                          <Check size={18} />
                        )}
                        {watched
                          ? `Undo episode ${show.progress + 1}`
                          : `Mark episode ${show.progress + 1} watched`}
                      </button>
                      <button
                        className="release-link"
                        ref={releaseLinkRef}
                        onClick={() => changeUpdates(true)}
                      >
                        <span className="update-dot" />
                        <span>2 updates since your last visit</span>
                        <ChevronRight size={15} />
                      </button>
                      <button
                        className="next-in-rotation"
                        onClick={() => openShow(nextShow.id)}
                        aria-label={`Try tracking ${nextShow.title}`}
                      >
                        <Image
                          unoptimized
                          src={`/images/${nextShow.poster}`}
                          width={42}
                          height={58}
                          alt=""
                        />
                        <span className="rotation-copy">
                          <span>ALSO IN YOUR COLLECTION</span>
                          <strong>{nextShow.title}</strong>
                          <span className="rotation-season">
                            Season {nextShow.season}
                          </span>
                        </span>
                        <ChevronRight size={16} />
                      </button>
                    </div>
                  )}
                </div>
              </TabsContent>
              <TabsContent value="library" className="showcase-panel">
                <div className="library-scene">
                  <div className="collection-shelf">
                    {shows.map((item) => {
                      const count =
                        item.progress + Number(Boolean(saved[item.id]));
                      return (
                        <button
                          className="collection-show"
                          key={item.id}
                          onClick={() => openShow(item.id)}
                          aria-label={`Try tracking ${item.title}`}
                          aria-describedby={`${item.id}-progress ${item.id}-status`}
                        >
                          <span className="collection-image">
                            <Image
                              unoptimized
                              src={`/images/${item.artwork}`}
                              width={980}
                              height={552}
                              alt={item.artAlt}
                              loading="lazy"
                            />
                            <span className="poster-invitation">
                              {count ? 'Pick up the story' : 'Start the story'}{' '}
                              <ArrowUpRight size={15} />
                            </span>
                          </span>
                          <span className="collection-caption">
                            <span className="collection-title">
                              {item.title}
                            </span>
                            <span id={`${item.id}-progress`}>
                              {String(count).padStart(2, '0')} / {item.episodes}
                            </span>
                          </span>
                          <span className="collection-progress">
                            <i
                              style={{
                                width: `${(count / item.episodes) * 100}%`,
                              }}
                            />
                          </span>
                          <span
                            className="collection-status"
                            id={`${item.id}-status`}
                          >
                            Season {item.season} ·{' '}
                            {count ? 'Watching' : 'Plan to watch'}
                          </span>
                        </button>
                      );
                    })}
                  </div>
                </div>
              </TabsContent>
              <TabsContent value="schedule" className="showcase-panel">
                <div className="schedule-scene">
                  <div className="schedule-calendar">
                    <span className="scene-overline">ON THE HORIZON</span>
                    <h2>
                      Worth
                      <br />
                      the wait.
                    </h2>
                    <div className="schedule-month">
                      <strong>September</strong>
                      <span>2026</span>
                    </div>
                    <div
                      className="schedule-week"
                      aria-label="Sample week, September 7 to 13, 2026"
                    >
                      {['M', 'T', 'W', 'T', 'F', 'S', 'S'].map((day, i) => (
                        <span key={i} className={i === 4 ? 'selected' : ''}>
                          {day}
                          <b>{i + 7}</b>
                        </span>
                      ))}
                    </div>
                    <p className="schedule-note">
                      Illustrative schedule · not current release dates
                    </p>
                  </div>
                  <div className="schedule-release">
                    <Image
                      unoptimized
                      src="/images/severance-wide.jpg"
                      width={980}
                      height={552}
                      alt="Severance sample release artwork"
                    />
                    <div className="release-date">
                      <b>11</b>
                      <span>SEP</span>
                    </div>
                    <div className="schedule-release-caption">
                      <span>FRIDAY · SAMPLE RELEASE</span>
                      <h3>Severance</h3>
                      <p>Season 2 · Episode 5</p>
                    </div>
                  </div>
                </div>
              </TabsContent>
            </div>
          </Tabs>
          <div className="showcase-bottom">
            <span aria-live="polite">
              {watched && view === 'today' && !updates
                ? `${show.title}: episode ${show.progress + 1} saved. Episode ${watchedCount + 1} is next.`
                : 'Choose a show. Try an episode.'}
            </span>
            <span>Sample data · Made for iPhone</span>
          </div>
        </div>
      </section>
    </>
  );
}
export function Questions() {
  return (
    <Accordion className="faq-list">
      {questions.map(({ q, a }, index) => (
        <AccordionItem value={String(index)} key={q}>
          <AccordionTrigger className="faq-trigger">{q}</AccordionTrigger>
          <AccordionContent keepMounted className="faq-content">
            <p>{a}</p>
          </AccordionContent>
        </AccordionItem>
      ))}
    </Accordion>
  );
}
