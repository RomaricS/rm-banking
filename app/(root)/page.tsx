import React from 'react';
import HeaderBox from '../../components/headerBox';
import TotalBalanceBox from '@/components/TotalBalanceBox';

const Home = () => {
  const loggedIn = {
    firstName: 'Jay',
  };

  return (
    <section className='home'>
      <div className='home-content'>
        <header className='home-header'>
          <HeaderBox
            type='greeting'
            title='Welcome'
            user={loggedIn.firstName ?? 'Guest'}
            subtext='Acces and manage your account and transactiosn efficiently'
          />
          <TotalBalanceBox
            accounts={[]}
            totalBanks={1}
            totalCurrentBalance={1000.85}
          />
        </header>
      </div>
    </section>
  );
};

export default Home;
